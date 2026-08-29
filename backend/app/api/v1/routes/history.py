"""GET /history — the authenticated user's automatic diet log (Phase 5.1).

Every ``POST /scan/verdict`` writes a ``scan_history`` row (see
``routes/scan.py``); this returns them paginated, most-recent-first, scoped to
the caller. There is no write endpoint here - logging is automatic.
"""

from __future__ import annotations

from fastapi import APIRouter, Query
from sqlalchemy import func, select

from app.api.deps import CurrentUser, DbSession
from app.models import AuditLog, ScanHistory
from app.schemas.scan import ScanHistoryItem, ScanHistoryPage

router = APIRouter(prefix="/history", tags=["history"])


@router.get("", response_model=ScanHistoryPage, operation_id="scan_history_list")
def list_history(
    user: CurrentUser,
    db: DbSession,
    limit: int = Query(20, ge=1, le=100, description="Page size."),
    offset: int = Query(0, ge=0, description="Rows to skip (most-recent-first)."),
):
    total = (
        db.scalar(
            select(func.count())
            .select_from(ScanHistory)
            .where(ScanHistory.user_id == user.id)
        )
        or 0
    )
    rows = db.scalars(
        select(ScanHistory)
        .where(ScanHistory.user_id == user.id)
        .order_by(ScanHistory.seq.desc())  # monotonic — stable most-recent-first
        .limit(limit)
        .offset(offset)
    ).all()

    db.add(
        AuditLog(user_id=user.id, action="read", resource="scan_history", status_code=200)
    )
    db.commit()

    return ScanHistoryPage(
        items=[ScanHistoryItem.model_validate(r) for r in rows],
        total=total,
        limit=limit,
        offset=offset,
        has_more=offset + len(rows) < total,
    )
