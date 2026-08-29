"""Phase 5.1 - automatic diet logging + GET /history.

Every completed POST /scan/verdict writes a scan_history row server-side, with
no separate "log this" call. GET /history returns them paginated,
most-recent-first, for the authenticated user only.
"""

from __future__ import annotations

import datetime as dt

import pytest
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core import crypto
from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import Allergy, Medication, User
from scripts.load_risk_tables import load_all

VERDICT = "/api/v1/scan/verdict"
HISTORY = "/api/v1/history"


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


def _auth(u: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token(u.id)}"}


def _scan(client, headers, *, name, ingredients=("Rolled oats",), nutriments=None,
          barcode=None):
    r = client.post(
        VERDICT,
        headers=headers,
        json={
            "ingredients": list(ingredients),
            "nutriments": nutriments or {},
            "product_name": name,
            "barcode": barcode,
        },
    )
    assert r.status_code == 200, r.text
    return r.json()


# --------------------------------------------------------------------------- #
def test_every_verdict_is_logged_automatically(client, db):
    u = _user(db, "+919101000001")
    h = _auth(u)

    # no "log this" call anywhere - just scan three products
    _scan(client, h, name="Rolled Oats")
    _scan(client, h, name="Iodised Table Salt", ingredients=["Iodised salt"],
          nutriments={"sodium_mg_100g": 1200})
    _scan(client, h, name="Sugar Biscuits", ingredients=["Wheat flour", "Sugar"],
          nutriments={"sugars_g_100g": 30})

    body = client.get(HISTORY, headers=h).json()
    assert body["total"] == 3
    assert len(body["items"]) == 3
    names = [it["product_name"] for it in body["items"]]
    assert set(names) == {"Rolled Oats", "Iodised Table Salt", "Sugar Biscuits"}
    first = body["items"][0]
    assert isinstance(first["score"], int)
    assert first["tier"] in {"safe", "caution", "avoid"}
    assert isinstance(first["key_reasons"], list)
    dt.datetime.fromisoformat(first["scanned_at"])  # parseable timestamp


def test_history_is_most_recent_first(client, db):
    u = _user(db, "+919101000002")
    h = _auth(u)
    _scan(client, h, name="First")
    _scan(client, h, name="Second")
    _scan(client, h, name="Third")

    items = client.get(HISTORY, headers=h).json()["items"]
    assert [it["product_name"] for it in items] == ["Third", "Second", "First"]
    ts = [dt.datetime.fromisoformat(it["scanned_at"]) for it in items]
    assert ts == sorted(ts, reverse=True)


def test_history_pagination(client, db):
    u = _user(db, "+919101000003")
    h = _auth(u)
    for i in range(5):
        _scan(client, h, name=f"Item {i}")

    page1 = client.get(HISTORY, headers=h, params={"limit": 2, "offset": 0}).json()
    assert page1["total"] == 5
    assert [it["product_name"] for it in page1["items"]] == ["Item 4", "Item 3"]
    assert page1["limit"] == 2 and page1["offset"] == 0 and page1["has_more"] is True

    page3 = client.get(HISTORY, headers=h, params={"limit": 2, "offset": 4}).json()
    assert [it["product_name"] for it in page3["items"]] == ["Item 0"]
    assert page3["has_more"] is False

    beyond = client.get(HISTORY, headers=h, params={"limit": 2, "offset": 99}).json()
    assert beyond["items"] == [] and beyond["has_more"] is False and beyond["total"] == 5


def test_history_is_scoped_to_the_caller(client, db):
    a = _user(db, "+919101000004")
    b = _user(db, "+919101000005")
    _scan(client, _auth(a), name="A's oats")
    _scan(client, _auth(a), name="A's salt", ingredients=["Iodised salt"])

    b_body = client.get(HISTORY, headers=_auth(b)).json()
    assert b_body["total"] == 0 and b_body["items"] == []

    a_body = client.get(HISTORY, headers=_auth(a)).json()
    assert a_body["total"] == 2
    assert all("A's" in it["product_name"] for it in a_body["items"])


def test_history_requires_auth(client):
    assert client.get(HISTORY).status_code == 401
    assert client.get(HISTORY, headers={"Authorization": "Bearer nope"}).status_code == 401


def test_hard_stop_verdict_is_logged_as_avoid(client, db):
    u = _user(db, "+919101000006")
    db.add(Allergy(user_id=u.id, allergen_name="Peanuts"))
    db.flush()
    h = _auth(u)
    _scan(client, h, name="Peanut Chikki", ingredients=["Groundnut", "Jaggery"])

    it = client.get(HISTORY, headers=h).json()["items"][0]
    assert it["tier"] == "avoid"
    assert it["hard_stop"] is True
    assert any("allergic to Peanuts" in r["title"] for r in it["key_reasons"])


def test_logged_columns_are_encrypted_at_rest(client, db):
    u = _user(db, "+919101000007")
    h = _auth(u)
    _scan(client, h, name="Secret Snack Brand", barcode="8901234567890",
          ingredients=["Wheat flour"])

    raw = db.execute(
        text("SELECT product_name, barcode, key_reasons FROM scan_history "
             "WHERE user_id = :uid"),
        {"uid": str(u.id)},
    ).one()
    assert raw.product_name.startswith("gAAAAA")   # Fernet token, not plaintext
    assert "Secret Snack Brand" not in raw.product_name
    assert raw.barcode.startswith("gAAAAA")
    assert crypto.decrypt(raw.product_name) == "Secret Snack Brand"
    assert crypto.decrypt(raw.barcode) == "8901234567890"

    # the API read path transparently decrypts
    it = client.get(HISTORY, headers=h).json()["items"][0]
    assert it["product_name"] == "Secret Snack Brand"


def test_history_rows_cascade_delete_with_the_account(client, db):
    u = _user(db, "+919101000008")
    h = _auth(u)
    _scan(client, h, name="Oats")
    _scan(client, h, name="Salt", ingredients=["Iodised salt"])
    assert db.scalar(
        text("SELECT count(*) FROM scan_history WHERE user_id = :u"), {"u": str(u.id)}
    ) == 2

    assert client.delete("/api/v1/me/account", headers=h).status_code == 204
    db.expire_all()
    assert db.scalar(
        text("SELECT count(*) FROM scan_history WHERE user_id = :u"), {"u": str(u.id)}
    ) == 0


def test_key_reasons_capped_and_ordered(client, db):
    u = _user(db, "+919101000009")
    # stack several factors so there are > 4 reasons
    db.add(Allergy(user_id=u.id, allergen_name="Peanuts"))
    db.add(Medication(user_id=u.id, name="Warfarin"))
    db.flush()
    h = _auth(u)
    _scan(
        client, h, name="Loaded Product",
        ingredients=["Groundnut", "Broccoli", "Iodised salt", "Sugar", "Zorblax powder"],
        nutriments={"sodium_mg_100g": 1200, "sugars_g_100g": 30},
    )
    row = db.scalars(
        text("SELECT id FROM scan_history WHERE user_id = :u"), {"u": str(u.id)}
    ).all()
    assert len(row) == 1
    kr = client.get(HISTORY, headers=h).json()["items"][0]["key_reasons"]
    assert 1 <= len(kr) <= 4
    assert kr[0]["kind"] == "allergen"  # most-serious-first preserved
