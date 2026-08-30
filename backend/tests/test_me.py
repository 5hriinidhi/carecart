"""GET / PATCH /me — the user's display name (Step 1: kill the hardcoded 'Aarav')."""

from __future__ import annotations

from app.core.security import create_access_token, hash_phone
from app.models import User

BASE = "/api/v1"


def _auth(db, phone: str) -> dict:
    u = User(phone_hash=hash_phone(phone))
    db.add(u)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(u.id)}"}


def test_me_is_null_name_until_set_then_round_trips(client, db):
    h = _auth(db, "+919612000001")
    assert client.get(f"{BASE}/me", headers=h).json() == {"display_name": None}

    r = client.patch(f"{BASE}/me", headers=h, json={"display_name": "  Priya  "})
    assert r.status_code == 200 and r.json()["display_name"] == "Priya"
    assert client.get(f"{BASE}/me", headers=h).json()["display_name"] == "Priya"


def test_me_name_is_cleaned_and_bounded(client, db):
    h = _auth(db, "+919612000002")
    assert client.patch(f"{BASE}/me", headers=h,
                        json={"display_name": "  \t  "}).status_code == 422
    assert client.patch(f"{BASE}/me", headers=h,
                        json={"display_name": "x" * 61}).status_code == 422
    assert client.patch(f"{BASE}/me", headers=h, json={}).status_code == 422
    assert client.patch(f"{BASE}/me", headers=h,
                        json={"phone": "123"}).status_code == 422  # extra=forbid


def test_me_requires_auth(client):
    assert client.get(f"{BASE}/me").status_code == 401
    assert client.patch(f"{BASE}/me", json={"display_name": "x"}).status_code == 401


def test_me_is_scoped_to_the_caller(client, db):
    a = _auth(db, "+919612000003")
    b = _auth(db, "+919612000004")
    client.patch(f"{BASE}/me", headers=a, json={"display_name": "Ada"})
    client.patch(f"{BASE}/me", headers=b, json={"display_name": "Bea"})
    assert client.get(f"{BASE}/me", headers=a).json()["display_name"] == "Ada"
    assert client.get(f"{BASE}/me", headers=b).json()["display_name"] == "Bea"
