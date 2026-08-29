"""Phase 5.3 VERIFICATION.

A) A user with 3 caution-tier scans that share ONE risk factor, inside a 10-day
   span -> exactly one nudge, message referencing THAT factor.
B) A user with 3 caution-tier scans spread across THREE different factors ->
   NO nudge (proves it's pattern-specific, not just a scan-count trigger).

Run:  pytest tests/test_nudges_verification.py -v -s
"""

from __future__ import annotations

import datetime as dt

import pytest
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import ScanHistory, User
from app.services import nudges as nudge_svc
from scripts.load_risk_tables import load_all

NUDGES = "/api/v1/nudges"


@pytest.fixture(scope="module", autouse=True)
def _ref(engine):
    with Session(engine) as s:
        load_all(s, settings.risk_data_path)
    yield


def _user(db, phone: str) -> User:
    u = User(phone_hash=hash_phone(phone))
    db.add(u)
    db.flush()
    return u


def _seed(db, user, *, factor: str, title: str, days_ago: int, name: str):
    db.add(ScanHistory(
        user_id=user.id, product_name=name, barcode=None, score=60, tier="caution",
        hard_stop=False,
        key_reasons=[{"kind": "condition_ceiling", "severity": "high",
                      "title": title, "factor": factor}],
        scanned_at=dt.datetime.now(dt.UTC) - dt.timedelta(days=days_ago),
    ))
    db.flush()


# --------------------------------------------------------------------------- #
def test_A_three_scans_one_factor_in_a_10_day_span_makes_one_specific_nudge(client, db):
    a = _user(db, "+919170000001")
    span = [(9, "P1"), (5, "P2"), (1, "P3")]     # 3 scans across an 8-day span, all <= 10
    for days_ago, name in span:
        _seed(db, a, factor="sodium", title="High sodium for Hypertension",
              days_ago=days_ago, name=name)

    created = nudge_svc.detect_and_record(db, a.id)
    db.commit()

    print("\n=== CASE A: 3 caution scans, all factor=sodium ===")
    for days_ago, name in span:
        print(f"  {name}  {days_ago}d ago  tier=caution  factor=sodium")
    print(f"nudges created: {len(created)}")
    for n in created:
        print(f"  factor={n.factor}  hit_count={n.hit_count}  window_days={n.window_days}")
        print(f"  message: {n.message}")

    assert len(created) == 1
    n = created[0]
    assert n.factor == "sodium"
    assert n.hit_count == 3
    assert "Sodium" in n.message                       # references the specific factor
    assert any(k in n.message.lower()
               for k in ("low-sodium", "unsalted", "rinse", "seasoning"))
    assert "worth swapping that group" not in n.message.lower()  # not the generic line

    h = {"Authorization": f"Bearer {create_access_token(a.id)}"}
    body = client.get(NUDGES, headers=h).json()
    assert [x["factor"] for x in body["items"]] == ["sodium"]
    assert "Sodium" in body["items"][0]["message"]


def test_B_three_scans_across_different_factors_make_NO_nudge(client, db):
    b = _user(db, "+919170000002")
    mix = [
        ("sodium", "High sodium for Hypertension", 8, "Salty snack"),
        ("added_sugar", "High Added / free sugars", 5, "Sweet drink"),
        ("saturated_fat", "Saturated fat is a poor fit for High cholesterol", 2, "Fried mix"),
    ]
    for factor, title, days_ago, name in mix:
        _seed(db, b, factor=factor, title=title, days_ago=days_ago, name=name)

    created = nudge_svc.detect_and_record(db, b.id)
    db.commit()

    # per-factor tally, as the detector sees it (each scan counts once per factor)
    tally: dict[str, int] = {}
    for factor, *_ in mix:
        tally[factor] = tally.get(factor, 0) + 1

    print("\n=== CASE B: 3 caution scans, one per factor ===")
    for factor, _title, days_ago, name in mix:
        print(f"  {name}  {days_ago}d ago  tier=caution  factor={factor}")
    print(f"per-factor tally: {tally}   (threshold is 3 for ONE factor)")
    print(f"nudges created: {len(created)}")

    assert created == []
    assert all(v < nudge_svc.MIN_HITS for v in tally.values())

    h = {"Authorization": f"Bearer {create_access_token(b.id)}"}
    body = client.get(NUDGES, headers=h).json()
    assert body["items"] == []
    assert body["latest_seq"] == 0
    print("OK: 3 scans, no single factor hit 3 -> no nudge. Pattern-specific, not a counter.")
