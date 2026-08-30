"""GET /drugs/search — searchable medicine catalogue (Step 3)."""

from __future__ import annotations

import pytest

from app.core.security import create_access_token, hash_phone
from app.models import DrugCatalog, User

BASE = "/api/v1"


def _auth(db, phone: str = "+919770000001") -> dict:
    u = User(phone_hash=hash_phone(phone))
    db.add(u)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(u.id)}"}


@pytest.fixture
def catalog(db):
    rows = [
        DrugCatalog(
            product_name="Ecosprin 75 Tablet",
            salt_composition="Aspirin (75mg)",
            active_ingredients="aspirin",
            drug_classes="NSAID",
        ),
        DrugCatalog(
            product_name="Ecosprin Gold 10 Capsule",
            salt_composition="Aspirin (75mg) + Atorvastatin (10mg)",
            active_ingredients="aspirin, atorvastatin",
            drug_classes="NSAID, Statin",
        ),
        DrugCatalog(
            product_name="Telma 40 Tablet",
            salt_composition="Telmisartan (40mg)",
            active_ingredients="telmisartan",
            drug_classes="ARB",
        ),
        DrugCatalog(
            product_name="Storvas 10 Tablet",
            salt_composition="Atorvastatin (10mg)",
            active_ingredients="atorvastatin",
            drug_classes="Statin",
        ),
    ]
    db.add_all(rows)
    db.flush()
    return rows


def test_search_requires_auth(client):
    assert client.get(f"{BASE}/drugs/search", params={"q": "eco"}).status_code == 401


def test_prefix_match_on_brand_name_comes_first(client, db, catalog):
    h = _auth(db)
    r = client.get(f"{BASE}/drugs/search", headers=h, params={"q": "ecospri"})
    assert r.status_code == 200
    names = [d["name"] for d in r.json()["results"]]
    assert names[:2] == ["Ecosprin 75 Tablet", "Ecosprin Gold 10 Capsule"]
    assert r.json()["results"][0]["salt_composition"] == "Aspirin (75mg)"


def test_matches_on_active_ingredient_too(client, db, catalog):
    h = _auth(db)
    r = client.get(f"{BASE}/drugs/search", headers=h, params={"q": "atorvastatin"})
    names = {d["name"] for d in r.json()["results"]}
    assert names == {"Storvas 10 Tablet", "Ecosprin Gold 10 Capsule"}


def test_short_query_is_rejected(client, db, catalog):
    h = _auth(db)
    assert client.get(f"{BASE}/drugs/search", headers=h,
                      params={"q": "e"}).status_code == 422


def test_limit_is_clamped(client, db, catalog):
    h = _auth(db)
    r = client.get(f"{BASE}/drugs/search", headers=h,
                   params={"q": "tablet", "limit": 1})
    assert len(r.json()["results"]) == 1
    assert client.get(f"{BASE}/drugs/search", headers=h,
                      params={"q": "tablet", "limit": 999}).status_code == 422


def test_like_wildcards_in_the_query_are_literal(client, db, catalog):
    h = _auth(db)
    # '%' must not act as a wildcard — nothing is literally named with a '%'
    r = client.get(f"{BASE}/drugs/search", headers=h, params={"q": "eco%pri"})
    assert r.status_code == 200
    assert r.json()["results"] == []


def test_empty_catalog_returns_empty_not_error(client, db):
    h = _auth(db)
    r = client.get(f"{BASE}/drugs/search", headers=h, params={"q": "aspirin"})
    assert r.status_code == 200
    assert r.json() == {"query": "aspirin", "results": []}
