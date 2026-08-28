"""Phase 3.2 — Health Identity Vault: schema, encryption at rest, ownership scoping."""

from __future__ import annotations

import json
import uuid

import pytest
from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy import text

from app.core import crypto
from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import User

BASE = "/api/v1"


def _make_user(db, phone: str) -> User:
    user = User(phone_hash=hash_phone(phone))
    db.add(user)
    db.flush()
    return user


@pytest.fixture
def user_a(db) -> User:
    return _make_user(db, "+919000000001")


@pytest.fixture
def user_b(db) -> User:
    return _make_user(db, "+919000000002")


@pytest.fixture
def auth_a(user_a) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user_a.id)}"}


@pytest.fixture
def auth_b(user_b) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user_b.id)}"}


# --------------------------------------------------------------- auth required --
@pytest.mark.parametrize(
    ("method", "path", "body"),
    [
        ("get", "/me/health-profile", None),
        ("put", "/me/health-profile", {}),
        ("get", "/me/conditions", None),
        ("post", "/me/conditions", {"condition_name": "x"}),
        ("get", "/me/allergies", None),
        ("post", "/me/allergies", {"allergen_name": "x"}),
        ("get", "/me/medications", None),
        ("post", "/me/medications", {"name": "x"}),
    ],
)
def test_every_endpoint_requires_a_jwt(client, method, path, body):
    kwargs = {} if body is None else {"json": body}
    r = getattr(client, method)(BASE + path, **kwargs)
    assert r.status_code == 401


def test_garbage_token_is_rejected(client):
    r = client.get(BASE + "/me/conditions", headers={"Authorization": "Bearer nope.nope.nope"})
    assert r.status_code == 401


# ------------------------------------------------------------ CRUD round-trips --
def test_health_profile_crud(client, auth_a):
    assert client.get(BASE + "/me/health-profile", headers=auth_a).status_code == 404

    body = {
        "gender": "female",
        "activity_level": "moderate",
        "body_metrics": {"weight": 62, "height": 165, "weight_unit": "kg", "height_unit": "cm"},
        "diet_type": ["low sodium", "vegetarian"],
    }
    assert client.put(BASE + "/me/health-profile", headers=auth_a, json=body).status_code == 200

    got = client.get(BASE + "/me/health-profile", headers=auth_a).json()
    assert got["gender"] == "female"
    assert got["body_metrics"]["weight"] == 62
    assert got["diet_type"] == ["low sodium", "vegetarian"]

    patched = client.patch(
        BASE + "/me/health-profile", headers=auth_a, json={"activity_level": "heavy"}
    ).json()
    assert patched["activity_level"] == "heavy"
    assert patched["gender"] == "female"  # untouched

    assert client.delete(BASE + "/me/health-profile", headers=auth_a).status_code == 204
    assert client.get(BASE + "/me/health-profile", headers=auth_a).status_code == 404


def test_condition_crud(client, auth_a):
    created = client.post(
        BASE + "/me/conditions", headers=auth_a, json={"condition_name": "Type 2 diabetes"}
    )
    assert created.status_code == 201
    cid = created.json()["id"]
    assert created.json()["condition_name"] == "Type 2 diabetes"

    listing = client.get(BASE + "/me/conditions", headers=auth_a).json()
    assert [c["condition_name"] for c in listing] == ["Type 2 diabetes"]

    upd = client.patch(
        BASE + f"/me/conditions/{cid}", headers=auth_a, json={"condition_name": "Hypertension"}
    )
    assert upd.json()["condition_name"] == "Hypertension"

    assert client.delete(BASE + f"/me/conditions/{cid}", headers=auth_a).status_code == 204
    assert client.get(BASE + "/me/conditions", headers=auth_a).json() == []


def test_medication_crud_with_dates(client, auth_a):
    created = client.post(
        BASE + "/me/medications",
        headers=auth_a,
        json={"name": "Telmisartan", "dosage": "40 mg", "active_from": "2026-02-01"},
    )
    assert created.status_code == 201
    body = created.json()
    assert body["name"] == "Telmisartan"
    assert body["dosage"] == "40 mg"
    assert body["active_from"] == "2026-02-01"
    assert body["active_to"] is None

    mid = body["id"]
    upd = client.patch(
        BASE + f"/me/medications/{mid}", headers=auth_a, json={"active_to": "2026-06-30"}
    ).json()
    assert upd["active_to"] == "2026-06-30"
    assert upd["name"] == "Telmisartan"


def test_allergy_crud(client, auth_a):
    r = client.post(BASE + "/me/allergies", headers=auth_a, json={"allergen_name": "Peanuts"})
    assert r.status_code == 201
    aid = r.json()["id"]
    listing = client.get(BASE + "/me/allergies", headers=auth_a).json()
    assert listing[0]["allergen_name"] == "Peanuts"
    assert client.delete(BASE + f"/me/allergies/{aid}", headers=auth_a).status_code == 204


# ------------------------------------------------------- encryption at rest --
def test_condition_name_is_ciphertext_in_the_database(client, db, auth_a):
    client.post(BASE + "/me/conditions", headers=auth_a, json={"condition_name": "Hypothyroidism"})

    raw = db.execute(text("SELECT condition_name FROM conditions")).scalar_one()
    assert raw != "Hypothyroidism"
    assert "Hypothyroid" not in raw
    assert raw.startswith("gAAAAA")  # Fernet token prefix
    assert crypto.decrypt(raw) == "Hypothyroidism"


def test_medication_name_and_dosage_are_ciphertext_in_the_database(client, db, auth_a):
    client.post(
        BASE + "/me/medications",
        headers=auth_a,
        json={"name": "Metformin", "dosage": "500 mg", "active_from": "2026-01-01"},
    )

    row = db.execute(text("SELECT name, dosage, active_from FROM medications")).one()
    assert "Metformin" not in row.name and row.name != "Metformin"
    assert "500" not in row.dosage
    assert crypto.decrypt(row.name) == "Metformin"
    assert crypto.decrypt(row.dosage) == "500 mg"
    assert str(row.active_from) == "2026-01-01"  # non-sensitive column: plaintext


def test_allergen_name_is_ciphertext_in_the_database(client, db, auth_a):
    # Phase 3 compliance note: every PHI column is encrypted at rest, allergies included.
    client.post(BASE + "/me/allergies", headers=auth_a, json={"allergen_name": "Shellfish"})
    raw = db.execute(text("SELECT allergen_name FROM allergies")).scalar_one()
    assert raw != "Shellfish" and "Shell" not in raw
    assert raw.startswith("gAAAAA")
    assert crypto.decrypt(raw) == "Shellfish"


def test_health_profile_fields_are_ciphertext_in_the_database(client, db, auth_a):
    client.put(
        BASE + "/me/health-profile",
        headers=auth_a,
        json={
            "gender": "female",
            "activity_level": "heavy",
            "body_metrics": {"weight": 61, "height": 165},
            "diet_type": ["low sodium", "jain"],
        },
    )
    row = db.execute(
        text("SELECT gender, activity_level, body_metrics, diet_type FROM health_profiles")
    ).one()
    for col in row:
        assert col.startswith("gAAAAA"), f"{col!r} is not encrypted"
    assert "female" not in row.gender
    assert "jain" not in row.diet_type
    assert crypto.decrypt(row.gender) == "female"
    assert json.loads(crypto.decrypt(row.diet_type)) == ["low sodium", "jain"]
    assert json.loads(crypto.decrypt(row.body_metrics))["weight"] == 61


def test_users_table_stores_a_phone_hash_not_the_number(client, db, auth_a, user_a):
    raw = db.execute(
        text("SELECT phone_hash FROM users WHERE id = :i"), {"i": user_a.id}
    ).scalar_one()
    assert raw == hash_phone("+919000000001")
    assert "9000000001" not in raw
    assert len(raw) == 64  # sha256 hex


# --------------------------------------------------- ownership / scoping --
def test_a_user_cannot_read_or_write_another_users_rows(client, auth_a, auth_b):
    a_med = client.post(
        BASE + "/me/medications", headers=auth_a, json={"name": "Atorvastatin", "dosage": "10 mg"}
    ).json()
    mid = a_med["id"]

    assert client.get(BASE + "/me/medications", headers=auth_b).json() == []
    assert client.get(BASE + f"/me/medications/{mid}", headers=auth_b).status_code == 404
    assert (
        client.patch(
            BASE + f"/me/medications/{mid}", headers=auth_b, json={"dosage": "80 mg"}
        ).status_code
        == 404
    )
    assert client.delete(BASE + f"/me/medications/{mid}", headers=auth_b).status_code == 404

    # A's row is exactly as A left it
    still = client.get(BASE + f"/me/medications/{mid}", headers=auth_a).json()
    assert still["dosage"] == "10 mg"


def test_health_profile_is_per_user(client, auth_a, auth_b):
    client.put(BASE + "/me/health-profile", headers=auth_a, json={"gender": "male"})
    assert client.get(BASE + "/me/health-profile", headers=auth_b).status_code == 404

    client.put(BASE + "/me/health-profile", headers=auth_b, json={"gender": "female"})
    assert client.get(BASE + "/me/health-profile", headers=auth_a).json()["gender"] == "male"


def test_collection_lists_are_filtered_to_the_caller(client, auth_a, auth_b):
    client.post(BASE + "/me/conditions", headers=auth_a, json={"condition_name": "A-only"})
    client.post(BASE + "/me/conditions", headers=auth_b, json={"condition_name": "B-only"})
    a_json = client.get(BASE + "/me/conditions", headers=auth_a).json()
    b_json = client.get(BASE + "/me/conditions", headers=auth_b).json()
    assert [c["condition_name"] for c in a_json] == ["A-only"]
    assert [c["condition_name"] for c in b_json] == ["B-only"]


def test_unknown_and_malformed_ids(client, auth_a):
    missing = uuid.uuid4()
    assert client.get(BASE + f"/me/conditions/{missing}", headers=auth_a).status_code == 404
    assert (
        client.patch(
            BASE + f"/me/conditions/{missing}", headers=auth_a, json={"condition_name": "x"}
        ).status_code
        == 404
    )
    assert client.delete(BASE + f"/me/conditions/{missing}", headers=auth_a).status_code == 404
    assert client.get(BASE + "/me/conditions/not-a-uuid", headers=auth_a).status_code == 422


# ------------------------------------------------------- crypto unit tests --
def test_fernet_roundtrip_and_tamper_detection():
    token = crypto.encrypt("secret condition")
    assert token != "secret condition"
    assert crypto.decrypt(token) == "secret condition"
    with pytest.raises(InvalidToken):
        crypto.decrypt(token[:-6] + "AAAAAA")


def test_key_rotation_old_key_still_decrypts(monkeypatch):
    old_key = Fernet.generate_key().decode()
    new_key = Fernet.generate_key().decode()

    monkeypatch.setattr(settings, "encryption_key", old_key)
    monkeypatch.setattr(settings, "encryption_keys_old", "")
    legacy_token = crypto.encrypt("written under the old key")

    # rotate: new key primary, old key retained for decryption only
    monkeypatch.setattr(settings, "encryption_key", new_key)
    monkeypatch.setattr(settings, "encryption_keys_old", old_key)

    assert crypto.decrypt(legacy_token) == "written under the old key"
    assert crypto.decrypt(crypto.encrypt("fresh")) == "fresh"


def test_encryption_key_is_loaded_from_settings_not_hardcoded():
    # the module reads the key from settings on every call
    import inspect

    src = inspect.getsource(crypto)
    assert "settings.encryption_key" in src
    # no 44-char base64 Fernet literal sitting in the crypto module
    assert "Fernet(b'" not in src and 'Fernet(b"' not in src
