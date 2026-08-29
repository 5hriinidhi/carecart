"""Phase 5.2 VERIFICATION - hand-checked weekly aggregates.

Seeds one user with 9 scans across THREE UTC weeks with a mix of tiers, calls
GET /analytics/trends, and asserts every returned weekly number against the
arithmetic done by hand below.

  Week A  Mon 2026-08-03   90 safe, 80 safe, 40 avoid
          -> n=3  safe/caution/avoid = 2/0/1  avg = (90+80+40)/3     = 70.0
  Week B  Mon 2026-08-10   60 caution, 50 caution, 70 safe, 30 avoid
          -> n=4  safe/caution/avoid = 1/2/1  avg = (60+50+70+30)/4 = 52.5
  Week C  Mon 2026-08-17   100 safe, 88 safe
          -> n=2  safe/caution/avoid = 2/0/0  avg = (100+88)/2       = 94.0

  Diet Health Score = EMA(alpha=0.2), seeded at the first score, folded in
  chronological order:
    90 -> 88.0 -> 78.4 -> 74.72 -> 69.776 -> 69.8208 -> 61.85664 -> 69.485312 -> 73.1882496
  bucket DHS = value as of the bucket's LAST scan (rounded):
    Week A (scan 3) round(78.4)      = 78
    Week B (scan 7) round(61.85664)  = 62
    Week C (scan 9) round(73.188...) = 73
  current DHS = round(73.188...) = 73
  7-day delta: last scan 2026-08-18 09:00; DHS as of <= 2026-08-11 09:00 is
    round(69.776) = 70  ->  73 - 70 = +3  -> "improving"

  Monthly (all 9, August): avg = 608 / 9 = 67.5555... -> 67.6 ; DHS = 73

Run:  pytest tests/test_analytics_trends_verification.py -v -s
"""

from __future__ import annotations

import datetime as dt

from app.core.security import create_access_token, hash_phone
from app.models import ScanHistory, User

URL = "/api/v1/analytics/trends"

# (iso date, hour, score, tier)
SEED = [
    ("2026-08-03", 9, 90, "safe"),
    ("2026-08-04", 9, 80, "safe"),
    ("2026-08-05", 9, 40, "avoid"),
    ("2026-08-10", 9, 60, "caution"),
    ("2026-08-11", 9, 50, "caution"),
    ("2026-08-12", 9, 70, "safe"),
    ("2026-08-13", 9, 30, "avoid"),
    ("2026-08-17", 9, 100, "safe"),
    ("2026-08-18", 9, 88, "safe"),
]


def test_weekly_aggregates_are_arithmetically_correct(client, db):
    u = User(phone_hash=hash_phone("+919140000001"))
    db.add(u)
    db.flush()
    for d, h, score, tier in SEED:
        db.add(ScanHistory(
            user_id=u.id, product_name=f"{d} {score}", barcode=None,
            score=score, tier=tier, hard_stop=(score == 0), key_reasons=[],
            scanned_at=dt.datetime.fromisoformat(d).replace(hour=h, tzinfo=dt.UTC),
        ))
    db.flush()

    body = client.get(
        URL, headers={"Authorization": f"Bearer {create_access_token(u.id)}"},
        params={"tz": "UTC"},
    ).json()

    print("\n--- raw seed ---")
    for d, h, score, tier in SEED:
        print(f"  {d} {h:02d}:00  score={score:3}  {tier}")

    print("\n--- API response ---")
    print(f"timezone={body['timezone']}  total_scans={body['total_scans']}  "
          f"DHS={body['diet_health_score']}  delta_7d={body['diet_health_score_delta_7d']}  "
          f"trend={body['trend']}")
    for w in body["weekly"]:
        sca = f"{w['safe']}/{w['caution']}/{w['avoid']}"
        print(f"  {w['period_start']} {w['label']:7} n={w['scans']} "
              f"avg={w['avg_score']:5} s/c/a={sca}  DHS={w['diet_health_score']}")
    for m in body["monthly"]:
        print(f"  month {m['period_start']} n={m['scans']} "
              f"avg={m['avg_score']} DHS={m['diet_health_score']}")

    # -------- top level --------
    assert body["timezone"] == "UTC"
    assert body["total_scans"] == 9
    assert body["diet_health_score"] == 73
    assert body["diet_health_score_delta_7d"] == 3
    assert body["trend"] == "improving"

    # -------- weekly, hand-checked --------
    expected_weeks = [
        # period_start, scans, avg, safe, caution, avoid, dhs
        ("2026-08-03", 3, 70.0, 2, 0, 1, 78),
        ("2026-08-10", 4, 52.5, 1, 2, 1, 62),
        ("2026-08-17", 2, 94.0, 2, 0, 0, 73),
    ]
    assert len(body["weekly"]) == 3
    for got, (ps, n, avg, s, c, a, dhs) in zip(body["weekly"], expected_weeks, strict=True):
        assert got["period_start"] == ps
        assert got["scans"] == n
        assert got["avg_score"] == avg
        assert (got["safe"], got["caution"], got["avoid"]) == (s, c, a)
        assert got["safe"] + got["caution"] + got["avoid"] == n   # counts partition the scans
        assert got["diet_health_score"] == dhs

    # -------- monthly, hand-checked --------
    assert len(body["monthly"]) == 1
    m = body["monthly"][0]
    assert m["period_start"] == "2026-08-01"
    assert m["scans"] == 9
    assert m["avg_score"] == 67.6            # 608 / 9 rounded to 1 dp
    assert m["diet_health_score"] == 73

    # -------- sums across weeks == monthly counts --------
    assert sum(w["scans"] for w in body["weekly"]) == 9
    assert sum(w["safe"] for w in body["weekly"]) == 5     # 90 80 70 100 88
    assert sum(w["caution"] for w in body["weekly"]) == 2  # 60 50
    assert sum(w["avoid"] for w in body["weekly"]) == 2    # 40 30
    assert (m["safe"], m["caution"], m["avoid"]) == (5, 2, 2)

    print("\nOK: every weekly average / count / rolling-score matches the hand arithmetic.")
