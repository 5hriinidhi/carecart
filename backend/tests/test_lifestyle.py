"""GET/PUT/PATCH/DELETE /me/lifestyle-profile."""

from __future__ import annotations

from app.core.security import create_access_token, hash_phone
from app.models import User

BASE = "/api/v1/me/lifestyle-profile"


def _auth(db, phone: str = "+919944000001") -> dict:
    u = User(phone_hash=hash_phone(phone))
    db.add(u)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(u.id)}"}


def test_404_until_set(client, db):
    h = _auth(db)
    assert client.get(BASE, headers=h).status_code == 404


def test_put_then_get_round_trips(client, db):
    h = _auth(db)
    body = {"sleep_hours": 7.5, "exercise_days": 4, "smoking": "none",
            "alcohol": "occasional", "stress": 3}
    r = client.put(BASE, headers=h, json=body)
    assert r.status_code == 200 and r.json() == body
    assert client.get(BASE, headers=h).json() == body


def test_put_replaces_and_omits_unanswered(client, db):
    h = _auth(db)
    client.put(BASE, headers=h, json={"sleep_hours": 8, "stress": 2})
    got = client.put(BASE, headers=h, json={"exercise_days": 5}).json()
    assert got == {"sleep_hours": None, "exercise_days": 5, "smoking": None,
                   "alcohol": None, "stress": None}


def test_patch_merges(client, db):
    h = _auth(db)
    client.put(BASE, headers=h, json={"sleep_hours": 8, "stress": 2})
    got = client.patch(BASE, headers=h, json={"stress": 4}).json()
    assert got["sleep_hours"] == 8 and got["stress"] == 4
    assert client.patch(BASE, headers=h, json={}).status_code == 422


def test_validation(client, db):
    h = _auth(db)
    assert client.put(BASE, headers=h, json={"stress": 6}).status_code == 422
    assert client.put(BASE, headers=h, json={"exercise_days": 8}).status_code == 422
    assert client.put(BASE, headers=h, json={"smoking": "sometimes"}).status_code == 422
    assert client.put(BASE, headers=h, json={"sleep_hours": 30}).status_code == 422
    assert client.put(BASE, headers=h, json={"weird": 1}).status_code == 422


def test_delete(client, db):
    h = _auth(db)
    client.put(BASE, headers=h, json={"stress": 3})
    assert client.delete(BASE, headers=h).status_code == 204
    assert client.get(BASE, headers=h).status_code == 404


def test_scoped_to_caller(client, db):
    a = _auth(db, "+919944000002")
    b = _auth(db, "+919944000003")
    client.put(BASE, headers=a, json={"stress": 1})
    client.put(BASE, headers=b, json={"stress": 5})
    assert client.get(BASE, headers=a).json()["stress"] == 1
    assert client.get(BASE, headers=b).json()["stress"] == 5


def test_fit_endpoint_shape_no_data(client, db):
    h = _auth(db)
    r = client.get("/api/v1/me/fit", headers=h)
    assert r.status_code == 200
    body = r.json()
    assert body["score"] is None  # nothing to score yet
    assert body["lifestyle"]["overall"] is None
    assert body["medicines"]["overall"] is None
    assert body["delta"] == 0


def test_fit_endpoint_with_lifestyle_only(client, db):
    h = _auth(db)
    client.put(BASE, headers=h, json={"sleep_hours": 8, "exercise_days": 5,
                                      "smoking": "none", "alcohol": "none",
                                      "stress": 2})
    body = client.get("/api/v1/me/fit", headers=h).json()
    assert body["score"] == body["lifestyle"]["overall"]
    assert body["tier"] == "well matched"
    assert len(body["lifestyle"]["dims"]) == 5
