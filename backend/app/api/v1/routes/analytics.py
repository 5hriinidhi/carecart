"""GET /analytics/trends — weekly & monthly aggregates + rolling Diet Health
Score from the authenticated user's scan_history (Phase 5.2).

Timezones: ``scanned_at`` is stored in UTC. Bucketing uses, in order:
``?tz=`` (IANA name; validated, then remembered on the user), ``?tz_offset_minutes=``
(a fixed offset for this request only), the user's stored ``timezone``, else UTC.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import select

from app.api.deps import CurrentUser, DbSession
from app.models import AuditLog, ScanHistory
from app.schemas.analytics import TrendsOut
from app.services import trends as trends_svc

router = APIRouter(prefix="/analytics", tags=["analytics"])


def _resolve_zone(db, user, tz: str | None, tz_offset_minutes: int | None) -> str:
    """Return the tz *name* to bucket in (what build_trends resolves)."""
    if tz:
        try:
            _, canonical = trends_svc.resolve_timezone(tz)
        except ValueError as exc:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc)
            ) from None
        if user.timezone != canonical:
            user.timezone = canonical  # learn it for next time (and other surfaces)
        return canonical
    if tz_offset_minutes is not None:
        # a fixed-offset zone for this request; not persisted (offsets drift w/ DST)
        sign = "+" if tz_offset_minutes >= 0 else "-"
        h, m = divmod(abs(tz_offset_minutes), 60)
        return f"UTC{sign}{h:02d}:{m:02d}"
    return user.timezone or "UTC"


@router.get("/trends", response_model=TrendsOut, operation_id="analytics_trends")
def get_trends(
    user: CurrentUser,
    db: DbSession,
    tz: str | None = Query(
        None, description="IANA timezone name, e.g. Asia/Kolkata. Remembered on the user."
    ),
    tz_offset_minutes: int | None = Query(
        None, ge=-840, le=840,
        description="Fallback: the client's current UTC offset in minutes (e.g. 330).",
    ),
):
    zone_name = _resolve_zone(db, user, tz, tz_offset_minutes)

    rows = db.execute(
        select(ScanHistory.score, ScanHistory.tier, ScanHistory.scanned_at)
        .where(ScanHistory.user_id == user.id)
        .order_by(ScanHistory.seq)
    ).all()

    result = trends_svc.build_trends(
        [(r.score, r.tier, r.scanned_at) for r in rows], zone_name
    )

    db.add(
        AuditLog(user_id=user.id, action="read", resource="analytics_trends",
                 status_code=200)
    )
    db.commit()

    return TrendsOut(
        timezone=result.timezone,
        total_scans=result.total_scans,
        diet_health_score=result.diet_health_score,
        diet_health_score_delta_7d=result.diet_health_score_delta_7d,
        trend=result.trend,
        weekly=[b.__dict__ for b in result.weekly],
        monthly=[b.__dict__ for b in result.monthly],
    )
