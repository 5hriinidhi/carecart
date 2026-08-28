"""Phase 3.2 verification — the three checks from the verification prompt.

  1. two users; A writes a medication; B's GET for A's medication returns
     403/404, never the data.
  2. a raw SQL SELECT on `medications` shows the sensitive columns stored
     encrypted (not human-readable).
  3. the app's normal read path decrypts and returns the original value.

Run:  pytest tests/test_vault_verification.py -v -s
"""

from __future__ import annotations

import pytest
from sqlalchemy import text

from app.core import crypto
from app.core.security import create_access_token, hash_phone
from app.models import User

BASE = "/api/v1"
PLAIN_NAME = "Warfarin"
PLAIN_DOSAGE = "5 mg"


def _make_user(db, phone: str) -> User:
    user = User(phone_hash=hash_phone(phone))
    db.add(user)
    db.flush()
    return user


@pytest.fixture
def user_a(db) -> User:
    return _make_user(db, "+919000000010")


@pytest.fixture
def user_b(db) -> User:
    return _make_user(db, "+919000000020")


@pytest.fixture
def auth_a(user_a) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user_a.id)}"}


@pytest.fixture
def auth_b(user_b) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user_b.id)}"}


@pytest.fixture
def a_medication_id(client, auth_a) -> str:
    """User A writes one medication record."""
    r = client.post(
        BASE + "/me/medications",
        headers=auth_a,
        json={"name": PLAIN_NAME, "dosage": PLAIN_DOSAGE, "active_from": "2026-01-15"},
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


# ---------------------------------------------------------------------------
# 1. cross-user isolation: B cannot read A's medication
# ---------------------------------------------------------------------------
def test_1_user_b_cannot_get_user_a_medications(client, auth_a, auth_b, a_medication_id):
    # by id -> not 200, and definitely not A's data
    by_id = client.get(BASE + f"/me/medications/{a_medication_id}", headers=auth_b)
    assert by_id.status_code in (403, 404)
    assert PLAIN_NAME not in by_id.text
    assert PLAIN_DOSAGE not in by_id.text

    # B's collection does not contain A's row
    b_list = client.get(BASE + "/me/medications", headers=auth_b)
    assert b_list.status_code == 200
    assert b_list.json() == []
    assert PLAIN_NAME not in b_list.text

    # B cannot mutate it either
    assert client.patch(
        BASE + f"/me/medications/{a_medication_id}", headers=auth_b, json={"dosage": "1 mg"}
    ).status_code in (403, 404)
    assert client.delete(
        BASE + f"/me/medications/{a_medication_id}", headers=auth_b
    ).status_code in (403, 404)

    # ...and A's record is exactly as A wrote it
    a_view = client.get(BASE + f"/me/medications/{a_medication_id}", headers=auth_a).json()
    assert a_view["name"] == PLAIN_NAME and a_view["dosage"] == PLAIN_DOSAGE
    print(
        f"[1] B GET /me/medications/{a_medication_id[:8]}… -> {by_id.status_code}; "
        f"B list -> []; A's record intact"
    )


# ---------------------------------------------------------------------------
# 2. raw SQL: the sensitive columns are ciphertext at rest
# ---------------------------------------------------------------------------
def test_2_raw_select_shows_encrypted_columns(client, db, auth_a, a_medication_id):
    row = db.execute(
        text("SELECT id, name, dosage, active_from FROM medications WHERE id = :i"),
        {"i": a_medication_id},
    ).one()

    print("\n[2] raw  SELECT id, name, dosage, active_from FROM medications;")
    print(f"      id          = {row.id}")
    print(f"      name        = {row.name}")
    print(f"      dosage      = {row.dosage}")
    print(f"      active_from = {row.active_from}   (non-sensitive column, plaintext)")

    # not human-readable, not the plaintext, looks like a Fernet token
    assert row.name != PLAIN_NAME and PLAIN_NAME not in row.name
    assert row.dosage != PLAIN_DOSAGE and "5 mg" not in row.dosage
    assert row.name.startswith("gAAAAA") and row.dosage.startswith("gAAAAA")
    assert len(row.name) > 80  # base64 Fernet token, not a short string
    # the non-sensitive date column IS readable
    assert str(row.active_from) == "2026-01-15"


# ---------------------------------------------------------------------------
# 3. the app's normal read path decrypts to the original value
# ---------------------------------------------------------------------------
def test_3_app_read_path_decrypts_to_original(client, db, auth_a, a_medication_id):
    # via the HTTP API (EncryptedString decrypts on ORM load)
    api = client.get(BASE + f"/me/medications/{a_medication_id}", headers=auth_a).json()
    assert api["name"] == PLAIN_NAME
    assert api["dosage"] == PLAIN_DOSAGE

    # and the stored ciphertext decrypts back with the app key
    ciphertext_name = db.execute(
        text("SELECT name FROM medications WHERE id = :i"), {"i": a_medication_id}
    ).scalar_one()
    assert crypto.decrypt(ciphertext_name) == PLAIN_NAME

    print(
        f"[3] GET /me/medications/{a_medication_id[:8]}… -> "
        f"name={api['name']!r} dosage={api['dosage']!r}; "
        f"crypto.decrypt(ciphertext) == {PLAIN_NAME!r}"
    )
