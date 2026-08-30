"""POST /scan/verdict — food-drug interaction & severity scoring (Phase 4.4).

Takes a product's decoded ingredients (+ per-100 g nutriments) and scores them
against the authenticated user's stored conditions, allergies and *active*
medications. Returns a 0-100 score, a tier (``safe``/``caution``/``avoid`` on
the exact Phase 2.1 thresholds), and a plain-language list of the reasons.

Reads the user's health vault, so it writes an ``audit_log`` row (who / when /
status — never the content), like every other ``/me/*`` health-data path.
"""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter
from sqlalchemy import select

from app.api.deps import CurrentUser, DbSession
from app.core.config import settings
from app.models import (
    Allergy,
    AuditLog,
    Condition,
    LifestyleProfile,
    Medication,
    ScanHistory,
)
from app.schemas.nudge import NudgeOut
from app.schemas.scan import (
    MedMatchOut,
    ScanVerdictIn,
    ScanVerdictOut,
    VerdictReasonOut,
)
from app.services import fit as fit_svc
from app.services import ingredient_risk
from app.services import nudges as nudge_svc
from app.services import verdict as verdict_svc

router = APIRouter(prefix="/scan", tags=["scan"])


def _active_medications(db, user_id, today: dt.date) -> list[str]:
    names: list[str] = []
    for m in db.scalars(select(Medication).where(Medication.user_id == user_id)).all():
        if m.active_from and m.active_from > today:
            continue
        if m.active_to and m.active_to < today:
            continue
        names.append(m.name)
    return names


@router.post("/verdict", response_model=ScanVerdictOut, operation_id="scan_verdict")
def scan_verdict(body: ScanVerdictIn, user: CurrentUser, db: DbSession):
    today = dt.date.today()
    conditions = list(
        db.scalars(
            select(Condition.condition_name).where(Condition.user_id == user.id)
        ).all()
    )
    allergies = list(
        db.scalars(
            select(Allergy.allergen_name).where(Allergy.user_id == user.id)
        ).all()
    )
    medications = _active_medications(db, user.id, today)

    # 7b: the lifestyle half of CareCart Fit amplifies nutrition deductions.
    lp = db.scalar(
        select(LifestyleProfile).where(LifestyleProfile.user_id == user.id)
    )
    lifestyle_scores = {
        d.key: d.score
        for d in fit_svc.compute_lifestyle(lp.data if lp else None).dims
    }

    resolution = ingredient_risk.resolve_ingredients(
        db,
        body.ingredients,
        nutriments=body.nutriments,
        sample_product=body.barcode or body.product_name,
        queue_unresolved=settings.risk_queue_unresolved,
    )
    v = verdict_svc.score_verdict(
        db,
        resolution=resolution,
        conditions=conditions,
        allergies=allergies,
        medications=medications,
        nutriments=body.nutriments,
        lifestyle_scores=lifestyle_scores,
    )

    # --- automatic diet logging (Phase 5.1) ---------------------------------
    # every completed verdict is written to scan_history here, in the same
    # transaction as the verdict itself. The client does NOT call a separate
    # "log this" endpoint - a scan that produced a verdict is, by definition,
    # something the user consumed / considered, so it is logged unconditionally.
    db.add(
        ScanHistory(
            user_id=user.id,
            product_name=(body.product_name or body.barcode or "Scanned product")[:200],
            barcode=body.barcode,
            score=v.score,
            tier=v.tier,
            hard_stop=v.hard_stop,
            key_reasons=[
                {"kind": r.kind, "severity": r.severity, "title": r.title,
                 "factor": r.factor}
                for r in v.reasons[:4]
            ],
            scanned_at=dt.datetime.now(dt.UTC),
        )
    )
    db.flush()  # the nudge detector's query must see the row just added

    # --- behavioural nudge detection (Phase 5.3) --------------------------
    new_nudges = nudge_svc.detect_and_record(db, user.id)

    # health-data access -> audit row (no content), same transaction
    db.add(
        AuditLog(user_id=user.id, action="read", resource="scan_verdict", status_code=200)
    )
    db.commit()

    fresh_nudge = NudgeOut.model_validate(new_nudges[-1]) if new_nudges else None

    return ScanVerdictOut(
        score=v.score,
        tier=v.tier,
        hard_stop=v.hard_stop,
        reasons=[
            VerdictReasonOut(
                kind=r.kind,
                severity=r.severity,
                points=r.points,
                title=r.title,
                detail=r.detail,
                factor=r.factor,
            )
            for r in v.reasons
        ],
        medications=[
            MedMatchOut(name=m.name, drug_classes=m.drug_classes, identified=m.identified)
            for m in v.medications
        ],
        risk_compounds=v.risk_compounds,
        unverified=v.unverified,
        unverified_count=len(v.unverified),
        lifestyle_applied=v.lifestyle_applied,
        nudge=fresh_nudge,
    )
