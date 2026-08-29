"""Phase 5.3 - rule-based behavioural nudge detector + GET /nudges.

3+ non-safe scans sharing a recurring factor inside a rolling 14-day window ->
one Nudge row with a specific, actionable message. Runs automatically after each
POST /scan/verdict.
"""

from __future__ import annotations

import datetime as dt

import pytest
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core import crypto
from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import Condition, ScanHistory, User
from app.services import nudges as nudge_svc
from scripts.load_risk_tables import load_all

VERDICT = "/api/v1/scan/verdict"
NUDGES = "/api/v1/nudges"

# a product that is high-sodium for a hypertensive -> caution, key_reason factor="sodium"
_SALTY = {"ingredients": ["Iodised salt", "Gram flour"], "nutriments": {"sodium_mg_100g": 1200}}
_SUGARY = {"ingredients": ["Wheat flour", "Sugar"], "nutriments": {"sugars_g_100g": 30}}


@pytest.fixture(scope="module", autouse=True)
def _ref(engine):
    with Session(engine) as s:
        load_all(s, settings.risk_data_path)
    yield


def _user(db, phone: str, *, hypertension: bool = True) -> User:
    u = User(phone_hash=hash_phone(phone))
    db.add(u)
    db.flush()
    if hypertension:
        db.add(Condition(user_id=u.id, condition_name="Hypertension"))
        db.flush()
    return u


def _h(u: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token(u.id)}"}


def _scan(client, h, name, spec=None) -> dict:
    spec = spec or _SALTY
    r = client.post(VERDICT, headers=h, json={
        "ingredients": spec["ingredients"], "nutriments": spec["nutriments"],
        "product_name": name,
    })
    assert r.status_code == 200, r.text
    return r.json()


# --------------------------------------------------------------------------- #
def test_three_salty_scans_generate_one_actionable_sodium_nudge(client, db):
    u = _user(db, "+919160000001")
    h = _h(u)

    b1 = _scan(client, h, "Namkeen A")
    b2 = _scan(client, h, "Namkeen B")
    assert b1["nudge"] is None and b2["nudge"] is None  # threshold not yet crossed

    # every scan so far must be non-safe and carry factor="sodium"
    assert b1["tier"] in ("caution", "avoid")
    assert any(r["factor"] == "sodium" for r in b1["reasons"])

    b3 = _scan(client, h, "Namkeen C")
    n = b3["nudge"]
    assert n is not None
    assert n["factor"] == "sodium"
    assert n["hit_count"] == 3
    assert n["window_days"] == 14

    # specific + actionable, NOT the generic fallback
    msg = n["message"]
    assert "Sodium" in msg
    assert any(k in msg.lower() for k in ("low-sodium", "unsalted", "rinse", "seasoning"))
    assert "worth swapping that group" not in msg.lower()  # the _GENERIC text

    # and it shows up on GET /nudges
    page = client.get(NUDGES, headers=h).json()
    assert page["latest_seq"] >= 1
    assert [x["factor"] for x in page["items"]] == ["sodium"]
    assert page["items"][0]["message"] == msg


def test_two_hits_do_not_nudge(client, db):
    u = _user(db, "+919160000002")
    h = _h(u)
    _scan(client, h, "A")
    b2 = _scan(client, h, "B")
    assert b2["nudge"] is None
    assert client.get(NUDGES, headers=h).json()["items"] == []


def test_nudge_is_not_repeated_for_the_same_factor_in_the_window(client, db):
    u = _user(db, "+919160000003")
    h = _h(u)
    _scan(client, h, "A")
    _scan(client, h, "B")
    b3 = _scan(client, h, "C")
    assert b3["nudge"] is not None
    b4 = _scan(client, h, "D")            # 4th salty scan
    assert b4["nudge"] is None            # already nudged for sodium this window
    assert len(client.get(NUDGES, headers=h).json()["items"]) == 1


def test_different_factors_are_counted_separately(client, db):
    u = _user(db, "+919160000004")
    h = _h(u)
    _scan(client, h, "salty 1")
    _scan(client, h, "salty 2")
    b = _scan(client, h, "sugary", spec=_SUGARY)   # sodium=2, added_sugar=1
    assert b["nudge"] is None
    assert client.get(NUDGES, headers=h).json()["items"] == []


def test_safe_scans_do_not_count_toward_the_threshold(client, db):
    u = _user(db, "+919160000005")
    h = _h(u)
    # a low-sodium product -> "sodium" may appear but tier is safe
    safe_spec = {"ingredients": ["Rolled oats"], "nutriments": {"sodium_mg_100g": 30}}
    _scan(client, h, "safe oats", spec=safe_spec)
    _scan(client, h, "salty 1")
    b = _scan(client, h, "salty 2")               # only 2 NON-safe sodium scans
    assert b["nudge"] is None
    b3 = _scan(client, h, "salty 3")              # now 3 non-safe
    assert b3["nudge"] is not None and b3["nudge"]["hit_count"] == 3


def test_only_the_rolling_14_day_window_counts(client, db):
    u = _user(db, "+919160000006")
    h = _h(u)
    old = dt.datetime.now(dt.UTC) - dt.timedelta(days=20)
    for i in range(2):
        db.add(ScanHistory(
            user_id=u.id, product_name=f"old {i}", barcode=None, score=60,
            tier="caution", hard_stop=False,
            key_reasons=[{"kind": "condition_ceiling", "severity": "high",
                          "title": "High sodium for Hypertension", "factor": "sodium"}],
            scanned_at=old,
        ))
    db.flush()

    _scan(client, h, "fresh 1")
    b = _scan(client, h, "fresh 2")   # 2 fresh + 2 stale-out-of-window -> no nudge
    assert b["nudge"] is None
    b3 = _scan(client, h, "fresh 3")  # 3 fresh
    assert b3["nudge"] is not None and b3["nudge"]["hit_count"] == 3


def test_nudges_are_scoped_per_user(client, db):
    a = _user(db, "+919160000007")
    b = _user(db, "+919160000008")
    for name in ("A1", "A2", "A3"):
        _scan(client, _h(a), name)
    assert len(client.get(NUDGES, headers=_h(a)).json()["items"]) == 1
    assert client.get(NUDGES, headers=_h(b)).json()["items"] == []
    assert client.get(NUDGES, headers=_h(b)).json()["latest_seq"] == 0


def test_since_cursor_polls_incrementally(client, db):
    u = _user(db, "+919160000009")
    h = _h(u)
    for name in ("s1", "s2", "s3"):
        _scan(client, h, name)
    page = client.get(NUDGES, headers=h).json()
    seq = page["items"][0]["seq"]
    assert client.get(NUDGES, headers=h, params={"since": seq}).json()["items"] == []
    assert len(client.get(NUDGES, headers=h, params={"since": seq - 1}).json()["items"]) == 1


def test_dismiss(client, db):
    u = _user(db, "+919160000010")
    h = _h(u)
    for name in ("d1", "d2", "d3"):
        _scan(client, h, name)
    nid = client.get(NUDGES, headers=h).json()["items"][0]["id"]

    assert client.post(f"{NUDGES}/{nid}/dismiss", headers=h).status_code == 204
    assert client.get(NUDGES, headers=h).json()["items"] == []
    incl = client.get(NUDGES, headers=h, params={"include_dismissed": True}).json()
    assert len(incl["items"]) == 1 and incl["items"][0]["dismissed_at"] is not None

    # dismissing again is idempotent; unknown / other-user's id -> 404
    assert client.post(f"{NUDGES}/{nid}/dismiss", headers=h).status_code == 204
    other = _user(db, "+919160000011")
    assert client.post(f"{NUDGES}/{nid}/dismiss", headers=_h(other)).status_code == 404
    assert client.post(
        f"{NUDGES}/00000000-0000-0000-0000-000000000000/dismiss", headers=h
    ).status_code == 404


def test_message_is_encrypted_at_rest(client, db):
    u = _user(db, "+919160000012")
    h = _h(u)
    for name in ("e1", "e2", "e3"):
        _scan(client, h, name)
    raw = db.execute(
        text("SELECT message FROM nudges WHERE user_id = :u"), {"u": str(u.id)}
    ).scalar_one()
    assert raw.startswith("gAAAAA")
    assert "Sodium" not in raw
    assert "Sodium" in crypto.decrypt(raw)


def test_nudges_cascade_delete_with_the_account(client, db):
    u = _user(db, "+919160000013")
    h = _h(u)
    for name in ("c1", "c2", "c3"):
        _scan(client, h, name)
    assert db.scalar(
        text("SELECT count(*) FROM nudges WHERE user_id = :u"), {"u": str(u.id)}
    ) == 1
    assert client.delete("/api/v1/me/account", headers=h).status_code == 204
    db.expire_all()
    assert db.scalar(
        text("SELECT count(*) FROM nudges WHERE user_id = :u"), {"u": str(u.id)}
    ) == 0


def test_generic_fallback_still_names_the_factor(db):
    # a factor with no bespoke template still gets a specific (count + name) line
    msg = nudge_svc._render("oxalate", "Oxalates", 4)
    assert "Oxalates" in msg and "4" in msg


def test_endpoints_require_auth(client):
    assert client.get(NUDGES).status_code == 401
    assert client.post(
        f"{NUDGES}/00000000-0000-0000-0000-000000000000/dismiss"
    ).status_code == 401
