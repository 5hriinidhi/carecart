"""GET /nudges — poll for behavioural nudges (Phase 5.3).

Nudges are generated server-side by ``services/nudges.detect_and_record`` after
each scan (see ``routes/scan.py``); there is no create endpoint. The client
polls this, shows the newest on the nudge screen, and — only if the user has
granted notification permission — may fire a local notification for a new one.
"""

from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import func, select

from app.api.deps import CurrentUser, DbSession
from app.models import AuditLog, Nudge
from app.schemas.nudge import NudgeOut, NudgesPage

router = APIRouter(prefix="/nudges", tags=["nudges"])


@router.get("", response_model=NudgesPage, operation_id="nudges_list")
def list_nudges(
    user: CurrentUser,
    db: DbSession,
    since: int = Query(0, ge=0, description="Only return nudges with seq > this."),
    include_dismissed: bool = Query(False),
):
    q = select(Nudge).where(Nudge.user_id == user.id, Nudge.seq > since)
    if not include_dismissed:
        q = q.where(Nudge.dismissed_at.is_(None))
    rows = db.scalars(q.order_by(Nudge.seq.desc()).limit(50)).all()

    latest = (
        db.scalar(select(func.max(Nudge.seq)).where(Nudge.user_id == user.id)) or 0
    )
    db.add(
        AuditLog(user_id=user.id, action="read", resource="nudges", status_code=200)
    )
    db.commit()
    return NudgesPage(
        items=[NudgeOut.model_validate(r) for r in rows], latest_seq=latest
    )


@router.post("/{nudge_id}/dismiss", status_code=status.HTTP_204_NO_CONTENT)
def dismiss_nudge(nudge_id: uuid.UUID, user: CurrentUser, db: DbSession) -> Response:
    nudge = db.scalar(
        select(Nudge).where(Nudge.id == nudge_id, Nudge.user_id == user.id)
    )
    if nudge is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Nudge not found.")
    if nudge.dismissed_at is None:
        nudge.dismissed_at = dt.datetime.now(dt.UTC)
    db.add(
        AuditLog(
            user_id=user.id, action="write", resource="nudges",
            resource_id=nudge_id, status_code=204,
        )
    )
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
