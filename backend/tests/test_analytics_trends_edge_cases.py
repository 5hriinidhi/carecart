"""Phase 5 edge cases for GET /analytics/trends:

* brand-new users with zero or one scan (no divide-by-zero, no broken chart),
* a single extreme outlier scan skewing an otherwise-good week,
* daylight-saving-time boundaries not shifting weekly buckets.
"""

from __future__ import annotations

import datetime as dt

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
        hard_stop=False, key_reasons=[], scanned_at=when,
    ))
    db.flush()


# --------------------------------------------------------------- zero / one scan
def test_zero_scans_returns_200_with_a_safe_empty_shape(client, db):
    u = _user(db, "+919140000001")
    r = client.get(URL, headers=_h(u), params={"tz": "Asia/Kolkata"})
    assert r.status_code == 200
    body = r.json()
    # no NaN / no crash from an empty mean; the client reads this as "empty state"
    assert body["total_scans"] == 0
    assert body["diet_health_score"] == 0
    assert body["diet_health_score_delta_7d"] == 0
    assert body["trend"] == "steady"
    assert body["weekly"] == [] and body["monthly"] == []


def test_one_scan_makes_one_valid_bucket_not_a_line(client, db):
    u = _user(db, "+919140000002")
    _scan(db, u, 82, "safe", dt.datetime(2026, 8, 4, 10, 0, tzinfo=dt.UTC))

    body = client.get(URL, headers=_h(u), params={"tz": "UTC"}).json()
    assert body["total_scans"] == 1
    assert body["diet_health_score"] == 82          # EMA seeded at the first score
    assert len(body["weekly"]) == 1
    b = body["weekly"][0]
    # a single-point bucket: every stat collapses to the one score, nothing null
    assert b["scans"] == 1
    assert b["avg_score"] == 82.0
    assert b["median_score"] == 82.0
    assert b["min_score"] == 82 and b["max_score"] == 82
    assert b["diet_health_score"] == 82
    # the Flutter card shows "not enough history for a line" for < 2 buckets;
    # here that's exactly one bucket, so no chart is attempted.


# --------------------------------------------------------------- outlier skew
def test_one_bad_scan_shows_up_as_median_min_not_just_a_dragged_mean(client, db):
    u = _user(db, "+919140000003")
    wk = dt.datetime(2026, 8, 3, 9, 0, tzinfo=dt.UTC)   # Mon 3 Aug
    for i, s in enumerate([90, 88, 92, 91]):
        _scan(db, u, s, "safe", wk + dt.timedelta(hours=i))
    _scan(db, u, 8, "avoid", wk + dt.timedelta(hours=5))  # the one bad scan

    b = client.get(URL, headers=_h(u), params={"tz": "UTC"}).json()["weekly"][0]
    assert b["scans"] == 5
    # mean is dragged well below the typical scan ...
    assert b["avg_score"] == 73.8
    # ... but median / min make the single outlier obvious instead of hidden
    assert b["median_score"] == 90.0
    assert b["min_score"] == 8 and b["max_score"] == 92
    # divergence the client uses to render the "one low scan skewed this" note
    assert abs(b["avg_score"] - b["median_score"]) >= 10


def test_diet_health_score_ema_recovers_from_an_outlier_the_mean_keeps():
    base = dt.datetime(2026, 8, 3, 9, 0, tzinfo=dt.UTC)
    # three good scans, one terrible one, then a run of good scans again
    scores = [90, 90, 90, 5] + [90] * 6
    rows = [
        ((s, "avoid" if s < 45 else "safe", base + dt.timedelta(hours=i)))
        for i, s in enumerate(scores)
    ]
    tr = T.build_trends(rows, "UTC")
    wk = tr.weekly[0]
    # the week's mean is permanently dragged down by the one 5 it contains
    assert wk.avg_score < 85
    assert wk.min_score == 5
    # the Diet Health Score (EMA) climbs back toward 90 after the outlier passes
    assert tr.diet_health_score >= 82
    assert tr.diet_health_score > wk.avg_score


# --------------------------------------------------------------- DST boundaries
def test_build_trends_buckets_each_scan_at_its_own_local_offset_across_dst():
    # US DST springs forward on Sun 8 Mar 2026 (02:00 EST -> 03:00 EDT).
    rows = [
        # 04:30 UTC on 1 Mar -> 23:30 Sat 28 Feb EST  -> local Monday 23 Feb
        (80, "safe", dt.datetime(2026, 3, 1, 4, 30, tzinfo=dt.UTC)),
        # 04:30 UTC on 9 Mar -> 00:30 Mon 9 Mar EDT   -> local Monday 9 Mar
        (80, "safe", dt.datetime(2026, 3, 9, 4, 30, tzinfo=dt.UTC)),
    ]
    tr = T.build_trends(rows, "America/New_York")
    starts = [b.period_start.isoformat() for b in tr.weekly]
    assert starts == ["2026-02-23", "2026-03-09"]


def test_iana_zone_is_dst_correct_where_a_cached_fixed_offset_would_not_be(client, db):
    u = _user(db, "+919140000004")
    # this instant is 00:30 Monday 9 Mar in New York *because* it's already EDT
    _scan(db, u, 75, "safe", dt.datetime(2026, 3, 9, 4, 30, tzinfo=dt.UTC))

    iana = client.get(URL, headers=_h(u), params={"tz": "America/New_York"}).json()
    # a fixed offset the app cached back in January (EST = -300) is DST-naive:
    # it would place the same scan at 23:30 Sunday -> the previous week
    fixed = client.get(URL, headers=_h(u), params={"tz_offset_minutes": -300}).json()

    assert iana["weekly"][0]["period_start"] == "2026-03-09"
    assert fixed["weekly"][0]["period_start"] == "2026-03-02"
    # each response is internally consistent; the IANA one is the correct week
    assert iana["total_scans"] == fixed["total_scans"] == 1


def test_fall_back_boundary_also_buckets_correctly():
    # US DST falls back on Sun 1 Nov 2026 (02:00 EDT -> 01:00 EST).
    rows = [
        # 03:30 UTC on 1 Nov -> 23:30 Sat 31 Oct EDT -> local Monday 26 Oct
        (70, "safe", dt.datetime(2026, 11, 1, 3, 30, tzinfo=dt.UTC)),
        # 05:30 UTC on 2 Nov -> 00:30 Mon 2 Nov EST  -> local Monday 2 Nov
        (70, "safe", dt.datetime(2026, 11, 2, 5, 30, tzinfo=dt.UTC)),
    ]
    tr = T.build_trends(rows, "America/New_York")
    starts = [b.period_start.isoformat() for b in tr.weekly]
    assert starts == ["2026-10-26", "2026-11-02"]
