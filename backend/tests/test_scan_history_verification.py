"""Phase 5.1 VERIFICATION.

User A (Hypertension, Peanut allergy, Warfarin) scans FIVE different products via
POST /scan/verdict — no "log this" call anywhere. GET /history then returns
exactly those 5, most-recent-first, with the right score / tier / top reason for
each. A second user B sees NONE of A's entries.

Run:  pytest tests/test_scan_history_verification.py -v -s
"""

from __future__ import annotations

import datetime as dt

import pytest
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import Allergy, Condition, Medication, User
from scripts.load_risk_tables import load_all

VERDICT = "/api/v1/scan/verdict"
HISTORY = "/api/v1/history"

# (product_name, ingredients, nutriments, expected_score, expected_tier,
#  expected_hard_stop, expected_top_reason_substring)
PRODUCTS = [
    ("Quaker Rolled Oats", ["Rolled oats"], {},
     100, "safe", False, "No conflicts found"),
    ("Haldiram Salted Namkeen", ["Iodised salt", "Gram flour"], {"sodium_mg_100g": 1200},
     62, "caution", False, "High sodium for Hypertension"),
    ("Fresh Broccoli Florets", ["Broccoli"], {},
     65, "caution", False, "interacts with Vitamin K"),
    ("Grandma's Peanut Chikki", ["Groundnut", "Jaggery"], {"sugars_g_100g": 40},
     0, "avoid", True, "allergic to Peanuts"),
    ("Britannia Sugar Biscuits", ["Wheat flour", "Sugar"], {"sugars_g_100g": 30},
     94, "safe", False, "High Added / free sugars"),
]


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


def _headers(u: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token(u.id)}"}


def test_five_scans_then_history_returns_exactly_those_five_in_order(client, db):
    user_a = _user(db, "+919120000001")
    db.add(Condition(user_id=user_a.id, condition_name="Hypertension"))
    db.add(Allergy(user_id=user_a.id, allergen_name="Peanuts"))
    db.add(Medication(user_id=user_a.id, name="Warfarin 5mg"))
    db.flush()
    ha = _headers(user_a)

    # ---- 5 scans, in order, NO separate "log this" call ----
    print("\n--- user A scans 5 products via POST /scan/verdict ---")
    for name, ings, nut, exp_score, exp_tier, exp_hs, _ in PRODUCTS:
        r = client.post(VERDICT, headers=ha, json={
            "ingredients": ings, "nutriments": nut, "product_name": name,
        })
        assert r.status_code == 200, r.text
        v = r.json()
        print(f"  {name:26} -> score={v['score']:3} tier={v['tier']:8} "
              f"hard_stop={v['hard_stop']}")
        assert v["score"] == exp_score, name
        assert v["tier"] == exp_tier, name
        assert v["hard_stop"] is exp_hs, name

    # ---- GET /history ----
    body = client.get(HISTORY, headers=ha).json()
    print("\n--- GET /history (user A) ---")
    print(f"total={body['total']} limit={body['limit']} offset={body['offset']} "
          f"has_more={body['has_more']}")
    for i, it in enumerate(body["items"]):
        top = it["key_reasons"][0]["title"] if it["key_reasons"] else "(none)"
        print(f"  [{i}] {it['product_name']:26} score={it['score']:3} "
              f"tier={it['tier']:8} hard_stop={it['hard_stop']}  scanned_at={it['scanned_at']}")
        print(f"       key_reasons[0]: {top}")

    assert body["total"] == 5
    assert len(body["items"]) == 5
    assert body["has_more"] is False

    # most-recent-first: reverse of the scan order
    expected = list(reversed(PRODUCTS))
    for it, (name, _, _, score, tier, hard_stop, reason_sub) in zip(
        body["items"], expected, strict=True
    ):
        assert it["product_name"] == name
        assert it["score"] == score
        assert it["tier"] == tier
        assert it["hard_stop"] is hard_stop
        assert it["key_reasons"], f"{name}: expected at least one key reason"
        assert reason_sub in it["key_reasons"][0]["title"], (
            f"{name}: top reason {it['key_reasons'][0]['title']!r} "
            f"missing {reason_sub!r}"
        )

    # timestamps strictly descending
    ts = [dt.datetime.fromisoformat(it["scanned_at"]) for it in body["items"]]
    assert ts == sorted(ts, reverse=True)
    assert all(a >= b for a, b in zip(ts, ts[1:], strict=False))

    # ---- user B: a different user, sees NONE of A's entries ----
    user_b = _user(db, "+919120000002")
    hb = _headers(user_b)

    b_empty = client.get(HISTORY, headers=hb).json()
    print("\n--- GET /history (user B, before scanning) ---")
    print(f"total={b_empty['total']} items={b_empty['items']}")
    assert b_empty["total"] == 0
    assert b_empty["items"] == []

    # B does its own scan; its history has ONLY that, none of A's 5
    client.post(VERDICT, headers=hb, json={
        "ingredients": ["Water"], "nutriments": {}, "product_name": "B's Bottled Water",
    })
    b_after = client.get(HISTORY, headers=hb).json()
    print("\n--- GET /history (user B, after 1 scan) ---")
    for it in b_after["items"]:
        print(f"  {it['product_name']} score={it['score']} tier={it['tier']}")
    assert b_after["total"] == 1
    assert b_after["items"][0]["product_name"] == "B's Bottled Water"
    a_names = {name for name, *_ in PRODUCTS}
    assert not any(it["product_name"] in a_names for it in b_after["items"])

    # and A's history is still exactly its own 5, unchanged by B's scan
    a_again = client.get(HISTORY, headers=ha).json()
    assert a_again["total"] == 5
    assert [it["product_name"] for it in a_again["items"]] == [
        n for n, *_ in reversed(PRODUCTS)
    ]
    print("\nOK: A has exactly its 5 (ordered), B has only its own 1, no cross-leak.")
