"""Phase 5.2 - GET /analytics/trends: weekly/monthly aggregates + rolling
Diet Health Score, with consistent timezone bucketing.
"""

from __future__ import annotations

import datetime as dt

import pytest

from app.core.security import create_access_token, hash_phone
from app.models import ScanHistory, User
from app.services import trends as T

URL = "/api/v1/analytics/trends"


def _user(db, phone: str) -> User:
    u = User(phone_hash=hash_phone(phone))
    db.add(u)
    db.flush()
    return u


def _h(u: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token(u.id)}"}


def _scan(db, user, score: int, tier: str, when: dt.datetime):
    db.add(ScanHistory(
        user_id=user.id, product_name="p", barcode=None, score=score, tier=tier,
        hard_stop=(tier == "avoid" and score == 0), key_reasons=[],
        scanned_at=when,
    ))
    db.flush()


# --------------------------------------------------------------- unit: build_trends
def test_diet_health_score_is_an_ema_of_scores():
    base = dt.datetime(2026, 8, 24, 12, 0, tzinfo=dt.UTC)
    rows = [
        (50, "caution", base),
        (60, "caution", base + dt.timedelta(hours=1)),
        (70, "safe", base + dt.timedelta(hours=2)),
    ]
    tr = T.build_trends(rows, "UTC")
    # 50 -> 0.2*60+0.8*50 = 52 -> 0.2*70+0.8*52 = 55.6 -> 56
    assert tr.diet_health_score == 56
    assert tr.total_scans == 3
    assert tr.trend == "steady"  # all within 7 days


def test_trend_is_improving_when_recent_scores_climb():
    start = dt.datetime(2026, 7, 1, 9, 0, tzinfo=dt.UTC)
    rows = [(30, "avoid", start + dt.timedelta(days=i)) for i in range(10)]  # ~2 weeks of 30s
    rows += [(90, "safe", start + dt.timedelta(days=20 + i)) for i in range(6)]  # then 90s
    tr = T.build_trends(rows, "UTC")
    assert tr.diet_health_score > 60
    assert tr.diet_health_score_delta_7d > 0
    assert tr.trend == "improving"


def test_empty_history_is_zeroed():
    tr = T.build_trends([], "UTC")
    assert tr.total_scans == 0 and tr.diet_health_score == 0
    assert tr.trend == "steady" and tr.weekly == [] and tr.monthly == []


def test_resolve_timezone_forms():
    assert T.resolve_timezone(None)[1] == "UTC"
    assert T.resolve_timezone("Asia/Kolkata")[1] == "Asia/Kolkata"
    tzinfo, name = T.resolve_timezone("UTC+05:30")
    assert name == "UTC+05:30"
    assert tzinfo.utcoffset(None) == dt.timedelta(hours=5, minutes=30)
    with pytest.raises(ValueError):
        T.resolve_timezone("Mars/Olympus_Mons")


# ------------------------------------------------------------------- endpoint
def test_weekly_and_monthly_aggregates(client, db):
    u = _user(db, "+919130000001")
    wk = dt.datetime(2026, 8, 3, 12, 0, tzinfo=dt.UTC)  # Mon 3 Aug
    # week of 3 Aug: 2 safe + 1 caution
    _scan(db, u, 90, "safe", wk)
    _scan(db, u, 80, "safe", wk + dt.timedelta(days=1))
    _scan(db, u, 50, "caution", wk + dt.timedelta(days=2))
    # week of 10 Aug: 1 avoid
    _scan(db, u, 20, "avoid", wk + dt.timedelta(days=7))

    body = client.get(URL, headers=_h(u), params={"tz": "UTC"}).json()
    assert body["timezone"] == "UTC"
    assert body["total_scans"] == 4
    assert len(body["weekly"]) == 2

    w0, w1 = body["weekly"]
    assert w0["period_start"] == "2026-08-03"
    assert w0["scans"] == 3 and w0["safe"] == 2 and w0["caution"] == 1 and w0["avoid"] == 0
    assert w0["avg_score"] == pytest.approx((90 + 80 + 50) / 3, abs=0.05)
    assert w1["period_start"] == "2026-08-10"
    assert w1["scans"] == 1 and w1["avoid"] == 1

    assert len(body["monthly"]) == 1
    assert body["monthly"][0]["period_start"] == "2026-08-01"
    assert body["monthly"][0]["scans"] == 4
    # DHS present on every bucket, 0..100
    for b in body["weekly"] + body["monthly"]:
        assert 0 <= b["diet_health_score"] <= 100


def test_timezone_changes_the_weekly_bucket_boundary(client, db):
    u = _user(db, "+919130000002")
    # 22:00 UTC on a Sunday -> still that ISO week in UTC, but the NEXT week
    # in Asia/Kolkata (03:30 Monday local).
    instant = dt.datetime(2026, 8, 23, 22, 0, tzinfo=dt.UTC)
    assert instant.weekday() == 6  # Sunday, sanity
    _scan(db, u, 70, "safe", instant)

    utc = client.get(URL, headers=_h(u), params={"tz": "UTC"}).json()
    ist = client.get(URL, headers=_h(u), params={"tz": "Asia/Kolkata"}).json()

    assert utc["weekly"][0]["period_start"] == "2026-08-17"   # Mon before
    assert ist["weekly"][0]["period_start"] == "2026-08-24"   # Mon after (local Monday)
    # same single scan, different bucket start — but each request is internally
    # consistent and stable
    assert utc["total_scans"] == ist["total_scans"] == 1


def test_tz_query_param_is_remembered_on_the_user(client, db):
    u = _user(db, "+919130000003")
    assert u.timezone is None
    client.get(URL, headers=_h(u), params={"tz": "America/New_York"})
    db.expire(u)
    assert u.timezone == "America/New_York"
    # a later call with no tz uses the stored one
    body = client.get(URL, headers=_h(u)).json()
    assert body["timezone"] == "America/New_York"


def test_tz_offset_minutes_is_used_but_not_persisted(client, db):
    u = _user(db, "+919130000004")
    body = client.get(URL, headers=_h(u), params={"tz_offset_minutes": 330}).json()
    assert body["timezone"] == "UTC+05:30"
    db.expire(u)
    assert u.timezone is None  # offsets drift with DST — not remembered


def test_invalid_tz_is_422(client, db):
    u = _user(db, "+919130000005")
    r = client.get(URL, headers=_h(u), params={"tz": "Not/AZone"})
    assert r.status_code == 422


def test_rolling_score_matches_the_last_scan_bucket(client, db):
    u = _user(db, "+919130000006")
    base = dt.datetime(2026, 8, 3, 9, 0, tzinfo=dt.UTC)
    for i, sc in enumerate([40, 40, 40, 90, 90, 90]):
        tier = "safe" if sc >= 70 else "avoid"
        _scan(db, u, sc, tier, base + dt.timedelta(days=i))
    body = client.get(URL, headers=_h(u), params={"tz": "UTC"}).json()
    # rolling score climbed from 40 toward 90; the last weekly bucket's DHS
    # equals the top-level current score
    assert body["diet_health_score"] == body["weekly"][-1]["diet_health_score"]
    assert 40 < body["diet_health_score"] < 90


def test_empty_history_endpoint(client, db):
    u = _user(db, "+919130000007")
    body = client.get(URL, headers=_h(u)).json()
    assert body == {
        "timezone": "UTC", "total_scans": 0, "diet_health_score": 0,
        "diet_health_score_delta_7d": 0, "trend": "steady",
        "weekly": [], "monthly": [],
    }


def test_requires_auth(client):
    assert client.get(URL).status_code == 401
