"""Health Identity Vault CRUD (Phase 3.2).

Every endpoint requires a valid access token from 3.1 (``CurrentUser``) and is
scoped to that user: list queries filter ``user_id == current_user.id``, and
single-row lookups match on ``(id, user_id)`` together — so one user can never
read or write another user's rows, and a wrong / foreign id is an honest 404.

NOTE: no ``from __future__ import annotations`` here — FastAPI needs the route
parameter annotations (the per-resource pydantic schemas passed into the
factory) to be real objects, not strings.
"""

import uuid

from fastapi import APIRouter, File, HTTPException, Response, UploadFile, status
from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.api.deps import CurrentUser, DbSession
from app.api.uploads import read_image_upload
from app.core.config import settings
from app.db.base import Base
from app.models import (
    Allergy,
    AuditLog,
    Condition,
    HealthProfile,
    LifestyleProfile,
    Medication,
    User,
)
from app.schemas.fit import FitOut
from app.schemas.lifestyle import LifestyleIn, LifestyleOut, LifestylePatch
from app.services.fit import compute_fit
from app.services import verdict as verdict_svc
from app.schemas.vault import (
    AllergyIn,
    AllergyOut,
    AllergyPatch,
    ConditionIn,
    ConditionOut,
    ConditionPatch,
    HealthProfileIn,
    HealthProfileOut,
    HealthProfilePatch,
    MedicationIn,
    MedicationMappingItem,
    MedicationOut,
    MedicationPatch,
    MedicationScanOut,
    MeOut,
    MePatch,
)
from app.services import ocr


def _owned_or_404(db, model: type[Base], item_id: uuid.UUID, user_id: uuid.UUID):
    row = db.scalar(
        select(model).where(model.id == item_id, model.user_id == user_id)
    )
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"{model.__name__} not found.")
    return row


def _audit(db, user_id, action: str, resource: str, *, resource_id=None, status_code: int = 200):
    """Append a who/what/when row. No health-data *content* is recorded - only
    the acting user, the verb, the resource kind, the row id and the status.
    The caller's commit persists it in the same transaction."""
    db.add(
        AuditLog(
            user_id=user_id,
            action=action,
            resource=resource,
            resource_id=resource_id,
            status_code=status_code,
        )
    )


def _collection_router(*, model, schema_in, schema_patch, schema_out, prefix, tag):
    """A standard owned-collection CRUD router: GET / POST / GET{id} / PATCH{id} / DELETE{id}.
    Every operation is ownership-scoped and writes an audit row."""
    r = APIRouter(prefix=prefix, tags=[tag])

    @r.get("", response_model=list[schema_out], operation_id=f"{tag}_list")
    def list_items(user: CurrentUser, db: DbSession):
        rows = db.scalars(
            select(model).where(model.user_id == user.id).order_by(model.created_at)
        ).all()
        _audit(db, user.id, "read", tag)
        db.commit()
        return rows

    @r.post(
        "",
        response_model=schema_out,
        status_code=status.HTTP_201_CREATED,
        operation_id=f"{tag}_create",
    )
    def create_item(body: schema_in, user: CurrentUser, db: DbSession):
        row = model(user_id=user.id, **body.model_dump())
        db.add(row)
        db.flush()
        _audit(db, user.id, "write", tag, resource_id=row.id, status_code=201)
        db.commit()
        db.refresh(row)
        return row

    @r.get("/{item_id}", response_model=schema_out, operation_id=f"{tag}_get")
    def get_item(item_id: uuid.UUID, user: CurrentUser, db: DbSession):
        row = _owned_or_404(db, model, item_id, user.id)
        _audit(db, user.id, "read", tag, resource_id=item_id)
        db.commit()
        return row

    @r.patch("/{item_id}", response_model=schema_out, operation_id=f"{tag}_update")
    def update_item(item_id: uuid.UUID, body: schema_patch, user: CurrentUser, db: DbSession):
        row = _owned_or_404(db, model, item_id, user.id)
        data = body.model_dump(exclude_unset=True)
        if not data:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "No fields to update.")
        for field, value in data.items():
            setattr(row, field, value)
        _audit(db, user.id, "write", tag, resource_id=item_id)
        db.commit()
        db.refresh(row)
        return row

    @r.delete(
        "/{item_id}",
        status_code=status.HTTP_204_NO_CONTENT,
        operation_id=f"{tag}_delete",
    )
    def delete_item(item_id: uuid.UUID, user: CurrentUser, db: DbSession) -> Response:
        row = _owned_or_404(db, model, item_id, user.id)
        _audit(db, user.id, "delete", tag, resource_id=item_id, status_code=204)
        db.delete(row)
        db.commit()
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    return r


# --------------------------------------------------------- health profile (1:1)
health_profile_router = APIRouter(prefix="/me/health-profile", tags=["health-profile"])


def _my_profile(db, user_id: uuid.UUID) -> HealthProfile | None:
    return db.scalar(select(HealthProfile).where(HealthProfile.user_id == user_id))


@health_profile_router.get("", response_model=HealthProfileOut)
def get_health_profile(user: CurrentUser, db: DbSession):
    profile = _my_profile(db, user.id)
    if profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No health profile yet.")
    _audit(db, user.id, "read", "health_profile", resource_id=profile.id)
    db.commit()
    return profile


@health_profile_router.put("", response_model=HealthProfileOut)
def upsert_health_profile(body: HealthProfileIn, user: CurrentUser, db: DbSession):
    # Atomic upsert on the unique (user_id) index, so two devices PUTting the
    # profile at once can't 500 or create two rows — last write wins, one row.
    payload = {
        "gender": body.gender,
        "activity_level": body.activity_level,
        "body_metrics": body.body_metrics.model_dump(),
        "diet_type": list(body.diet_type),
    }
    db.execute(
        pg_insert(HealthProfile)
        .values(user_id=user.id, **payload)
        .on_conflict_do_update(
            index_elements=["user_id"],
            set_={**payload, "updated_at": func.now()},
        )
    )
    _audit(db, user.id, "write", "health_profile")
    db.commit()
    return _my_profile(db, user.id)


@health_profile_router.patch("", response_model=HealthProfileOut)
def patch_health_profile(body: HealthProfilePatch, user: CurrentUser, db: DbSession):
    profile = _my_profile(db, user.id)
    if profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No health profile yet.")
    data = body.model_dump(exclude_unset=True)
    if not data:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "No fields to update.")
    for field, value in data.items():
        setattr(profile, field, value)
    _audit(db, user.id, "write", "health_profile", resource_id=profile.id)
    db.commit()
    db.refresh(profile)
    return profile


@health_profile_router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def delete_health_profile(user: CurrentUser, db: DbSession) -> Response:
    profile = _my_profile(db, user.id)
    if profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No health profile yet.")
    _audit(db, user.id, "delete", "health_profile", resource_id=profile.id, status_code=204)
    db.delete(profile)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ----------------------------------------------------- lifestyle profile (1:1)
lifestyle_router = APIRouter(prefix="/me/lifestyle-profile", tags=["lifestyle-profile"])


def _my_lifestyle(db, user_id: uuid.UUID) -> LifestyleProfile | None:
    return db.scalar(select(LifestyleProfile).where(LifestyleProfile.user_id == user_id))


@lifestyle_router.get("", response_model=LifestyleOut)
def get_lifestyle(user: CurrentUser, db: DbSession):
    row = _my_lifestyle(db, user.id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No lifestyle profile yet.")
    _audit(db, user.id, "read", "lifestyle_profile", resource_id=row.id)
    db.commit()
    return LifestyleOut.from_data(row.data)


@lifestyle_router.put("", response_model=LifestyleOut)
def put_lifestyle(body: LifestyleIn, user: CurrentUser, db: DbSession):
    row = _my_lifestyle(db, user.id)
    data = body.as_data()  # only the keys the caller set
    if row is None:
        row = LifestyleProfile(user_id=user.id, data=data)
        db.add(row)
    else:
        row.data = data  # PUT replaces
    _audit(db, user.id, "write", "lifestyle_profile")
    db.commit()
    db.refresh(row)
    return LifestyleOut.from_data(row.data)


@lifestyle_router.patch("", response_model=LifestyleOut)
def patch_lifestyle(body: LifestylePatch, user: CurrentUser, db: DbSession):
    patch = body.as_data()
    if not patch:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "No fields to update.")
    row = _my_lifestyle(db, user.id)
    if row is None:
        row = LifestyleProfile(user_id=user.id, data=patch)
        db.add(row)
    else:
        row.data = {**(row.data or {}), **patch}
    _audit(db, user.id, "write", "lifestyle_profile")
    db.commit()
    db.refresh(row)
    return LifestyleOut.from_data(row.data)


@lifestyle_router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def delete_lifestyle(user: CurrentUser, db: DbSession) -> Response:
    row = _my_lifestyle(db, user.id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No lifestyle profile yet.")
    _audit(db, user.id, "delete", "lifestyle_profile", resource_id=row.id, status_code=204)
    db.delete(row)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --------------------------------------------------- medication -> food mapping
med_mapping_router = APIRouter(prefix="/me/medications", tags=["medications"])


@med_mapping_router.get(
    "/mapping",
    response_model=list[MedicationMappingItem],
    operation_id="medications_mapping",
)
def medications_mapping(user: CurrentUser, db: DbSession):
    rows = db.scalars(
        select(Medication).where(Medication.user_id == user.id).order_by(Medication.created_at)
    ).all()
    rules = verdict_svc._load_rules(db)
    out: list[MedicationMappingItem] = []
    for m in rows:
        classes = verdict_svc._drug_classes_for(m.name, rules)
        compounds: list[str] = []
        seen: set[str] = set()
        for cls in classes:
            for rule in rules.interactions.get(cls, []):
                if rule.risk_compound in seen:
                    continue
                seen.add(rule.risk_compound)
                compounds.append(
                    rules.display.get(rule.risk_compound,
                                      rule.risk_compound.replace("_", " "))
                )
        out.append(
            MedicationMappingItem(
                name=m.name,
                identified=bool(classes),
                drug_classes=classes,
                interactions=sorted(compounds),
            )
        )
    _audit(db, user.id, "read", "medications")
    db.commit()
    return out


# ------------------------------------------------------------- CareCart Fit
fit_router = APIRouter(prefix="/me/fit", tags=["fit"])


@fit_router.get("", response_model=FitOut, operation_id="me_fit")
def get_fit(user: CurrentUser, db: DbSession):
    """Lifestyle + medicines correlation score. Read-only, computed on the fly
    from the stored lifestyle profile + recent scan history. No content is
    written; the audit row records only that Fit was read."""
    row = _my_lifestyle(db, user.id)
    result = compute_fit(db, user.id, lifestyle_data=row.data if row else None)
    _audit(db, user.id, "read", "fit")
    db.commit()
    return FitOut.from_result(result)


# ---------------------------------------------------------------- collections
conditions_router = _collection_router(
    model=Condition,
    schema_in=ConditionIn,
    schema_patch=ConditionPatch,
    schema_out=ConditionOut,
    prefix="/me/conditions",
    tag="conditions",
)

allergies_router = _collection_router(
    model=Allergy,
    schema_in=AllergyIn,
    schema_patch=AllergyPatch,
    schema_out=AllergyOut,
    prefix="/me/allergies",
    tag="allergies",
)

medications_router = _collection_router(
    model=Medication,
    schema_in=MedicationIn,
    schema_patch=MedicationPatch,
    schema_out=MedicationOut,
    prefix="/me/medications",
    tag="medications",
)


@medications_router.post(
    "/scan", response_model=MedicationScanOut, operation_id="medications_scan_label"
)
async def scan_medication_label(
    user: CurrentUser, db: DbSession, file: UploadFile = File(...)
):
    """OCR a medication-label photo and return a *guess* for the user to confirm.

    This never writes to the vault — the client shows the candidate, the user
    confirms/edits it, then saves it with ``POST /me/medications``.
    """
    image_bytes = await read_image_upload(file)  # 415 / 413 / 422 before OCR

    try:
        raw_text, mean_conf = ocr.extract_text(image_bytes)
    except ocr.InvalidImage:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "That file isn't a readable image."
        ) from None
    except ocr.OcrUnavailable:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, "Label scanning is temporarily unavailable."
        ) from None

    text, truncated = ocr.sanitize_text(raw_text, max_chars=settings.ocr_text_max_chars)
    guess = ocr.guess_medication(text, mean_conf)

    _audit(db, user.id, "read", "medication_scan")
    db.commit()

    return MedicationScanOut(
        name_candidate=guess.name_candidate,
        name_confidence=guess.name_confidence,
        dosage_candidate=guess.dosage_candidate,
        raw_text=text,
        raw_text_truncated=truncated,
        confirmation_required=True,
    )


# ---------------------------------------------------------------- account name
me_router = APIRouter(prefix="/me", tags=["me"])


@me_router.get("", response_model=MeOut)
def get_me(user: CurrentUser, db: DbSession):
    _audit(db, user.id, "read", "me")
    db.commit()
    return user


@me_router.patch("", response_model=MeOut)
def patch_me(body: MePatch, user: CurrentUser, db: DbSession):
    data = body.model_dump(exclude_unset=True)
    if not data:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "No fields to update.")
    for field, value in data.items():
        setattr(user, field, value)
    _audit(db, user.id, "write", "me")
    db.commit()
    db.refresh(user)
    return user


# ------------------------------------------------------------ delete account
account_router = APIRouter(prefix="/me/account", tags=["account"])


@account_router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def delete_my_account(user: CurrentUser, db: DbSession) -> Response:
    """Permanently delete the account and everything in the vault that belongs
    to it. This is a HARD delete, not a soft flag: the `users` row is removed and
    Postgres `ON DELETE CASCADE` takes `health_profiles`, `conditions`,
    `allergies`, `medications` and `refresh_tokens` with it. Not reversible.

    (Transient `otp_challenges` are keyed by phone, expire in minutes, and are
    swept within a day — there is no lasting personal data there to remove.)
    """
    db.execute(delete(User).where(User.id == user.id))
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


ROUTERS = [
    me_router,
    health_profile_router,
    lifestyle_router,
    fit_router,
    med_mapping_router,  # before medications_router so /mapping isn't seen as an {item_id}
    conditions_router,
    allergies_router,
    medications_router,
    account_router,
]
