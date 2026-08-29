"""Weekly / monthly aggregates + rolling Diet Health Score (Phase 5.2).

Pure functions over ``scan_history`` rows. All timestamps are stored in UTC;
bucketing is done in a caller-supplied ``tzinfo`` (the user's local zone if
known, else UTC) so week / month boundaries land on local midnight and don't
shift between requests.

**Diet Health Score** — a 0-100 rolling number recalculated on *every* scan: an
exponential moving average of the scan scores, seeded at the first scan's score.
``alpha = 0.2`` (~ the last 9 scans dominate), so it tracks recent behaviour
while still moving smoothly. Each weekly / monthly bucket also carries the DHS
value *as of its last scan*, which is what the trend line plots.
"""

from __future__ import annotations

import datetime as dt
import re
from dataclasses import dataclass, field
from statistics import fmean
from zoneinfo import ZoneInfo

_OFFSET_RE = re.compile(r"^UTC([+-])(\d{2}):(\d{2})$")

_DHS_ALPHA = 0.2
_TREND_EPS = 3          # +/- points from "steady"
_MAX_WEEKS = 26
_MAX_MONTHS = 12

_MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun",
           "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")


@dataclass
class Bucket:
    period_start: dt.date
    label: str
    scans: int
    avg_score: float
    safe: int
    caution: int
    avoid: int
    diet_health_score: int


@dataclass
class Trends:
    timezone: str
    total_scans: int
    diet_health_score: int
    diet_health_score_delta_7d: int
    trend: str                                  # improving | declining | steady
    weekly: list[Bucket] = field(default_factory=list)
    monthly: list[Bucket] = field(default_factory=list)


def _week_start(d: dt.date) -> dt.date:
    return d - dt.timedelta(days=d.weekday())   # Monday


def _month_start(d: dt.date) -> dt.date:
    return d.replace(day=1)


def _week_label(d: dt.date) -> str:
    return f"{d.day} {_MONTHS[d.month - 1]}"


def _month_label(d: dt.date) -> str:
    return f"{_MONTHS[d.month - 1]} {d.year}"


def _bucket(rows, key_fn, label_fn, cap: int) -> list[Bucket]:
    """rows: list of (local_dt, score, tier, dhs_int), chronological."""
    groups: dict[dt.date, list] = {}
    for local_dt, score, tier, dhs in rows:
        groups.setdefault(key_fn(local_dt.date()), []).append((score, tier, dhs))

    out: list[Bucket] = []
    for period_start in sorted(groups):
        entries = groups[period_start]
        scores = [e[0] for e in entries]
        tiers = [e[1] for e in entries]
        out.append(
            Bucket(
                period_start=period_start,
                label=label_fn(period_start),
                scans=len(entries),
                avg_score=round(fmean(scores), 1),
                safe=tiers.count("safe"),
                caution=tiers.count("caution"),
                avoid=tiers.count("avoid"),
                diet_health_score=entries[-1][2],   # DHS as of the last scan in the bucket
            )
        )
    return out[-cap:]


def resolve_timezone(name: str | None) -> tuple[dt.tzinfo, str]:
    """(tzinfo, canonical name). Accepts an IANA name ("Asia/Kolkata") or a
    fixed offset ("UTC+05:30"). Falls back to UTC. Raises ValueError on a
    non-empty but unrecognised value so the route can 422."""
    if not name or name.strip().upper() == "UTC":
        return dt.UTC, "UTC"
    name = name.strip()

    m = _OFFSET_RE.match(name)
    if m:
        sign, hh, mm = m.group(1), int(m.group(2)), int(m.group(3))
        delta = dt.timedelta(hours=hh, minutes=mm)
        return dt.timezone(-delta if sign == "-" else delta, name), name

    try:
        return ZoneInfo(name), name
    except Exception as exc:  # noqa: BLE001  (ZoneInfoNotFoundError / ValueError)
        raise ValueError(f"Unknown timezone: {name!r}") from exc


def build_trends(rows, tz_name: str) -> Trends:
    """rows: iterable of (score:int, tier:str, scanned_at:datetime[UTC]),
    ordered oldest-first (by insertion). ``tz_name`` is the resolved zone."""
    zone, canonical = resolve_timezone(tz_name)

    enriched: list[tuple[dt.datetime, int, str, int]] = []
    dhs: float | None = None
    for score, tier, scanned_at in rows:
        if scanned_at.tzinfo is None:
            scanned_at = scanned_at.replace(tzinfo=dt.UTC)
        dhs = float(score) if dhs is None else _DHS_ALPHA * score + (1 - _DHS_ALPHA) * dhs
        enriched.append((scanned_at.astimezone(zone), score, tier, round(dhs)))

    if not enriched:
        return Trends(
            timezone=canonical, total_scans=0, diet_health_score=0,
            diet_health_score_delta_7d=0, trend="steady",
        )

    current = enriched[-1][3]

    # trend: current DHS vs the DHS as of ~7 days before the latest scan
    cutoff = enriched[-1][0] - dt.timedelta(days=7)
    prior = current
    for local_dt, _s, _t, d in enriched:
        if local_dt <= cutoff:
            prior = d
        else:
            break
    delta = current - prior
    trend = (
        "improving" if delta >= _TREND_EPS
        else "declining" if delta <= -_TREND_EPS
        else "steady"
    )

    return Trends(
        timezone=canonical,
        total_scans=len(enriched),
        diet_health_score=current,
        diet_health_score_delta_7d=delta,
        trend=trend,
        weekly=_bucket(enriched, _week_start, _week_label, _MAX_WEEKS),
        monthly=_bucket(enriched, _month_start, _month_label, _MAX_MONTHS),
    )
