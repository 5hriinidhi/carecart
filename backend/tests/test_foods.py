"""GET /foods/search — searchable everyday-food dataset."""

from __future__ import annotations

import pytest

from app.core.security import create_access_token, hash_phone
from app.models import FoodCatalog, User

BASE = "/api/v1"


def _auth(db, phone: str = "+919880000001") -> dict:
    u = User(phone_hash=hash_phone(phone))
    db.add(u)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(u.id)}"}


@pytest.fixture
def foods(db):
    rows = [
        FoodCatalog(
            name="Poha",
            kind="dish",
            ingredients_text="Flattened rice, peanuts, onion, curry leaves",
            diet="vegetarian",
            course="snack",
            region="West",
            nutriments={},
        ),
        FoodCatalog(
            name="Palak Paneer",
            kind="dish",
            diet="vegetarian",
            course="main course",
            region="North",
            nutriments={},
        ),
        FoodCatalog(
            name="Hide & Seek",
            kind="packaged",
            brand="Parle",
            category="BISCUIT / COOKIES",
            ingredients_text="Refined wheat flour, sugar, cocoa solids",
            serving_size="100 g",
            nutriments={
                "energy_kcal_100g": 479.0,
                "sugars_g_100g": 32.5,
                "sodium_mg_100g": 114.0,
            },
        ),
        FoodCatalog(
            name="Dark Fantasy Bourbon",
            kind="packaged",
            brand="Sunfeast",
            category="BISCUIT / CREAM",
            nutriments={"energy_kcal_100g": 412.0},
        ),
    ]
    db.add_all(rows)
    db.flush()
    return rows


def test_search_requires_auth(client):
    assert client.get(f"{BASE}/foods/search", params={"q": "poha"}).status_code == 401


def test_name_prefix_ranks_first_and_carries_facts(client, db, foods):
    h = _auth(db)
    r = client.get(f"{BASE}/foods/search", headers=h, params={"q": "poha"})
    assert r.status_code == 200
    hit = r.json()["results"][0]
    assert hit["name"] == "Poha"
    assert hit["kind"] == "dish"
    assert hit["diet"] == "vegetarian"
    assert "Flattened rice" in hit["ingredients_text"]


def test_packaged_hit_returns_per_100g_nutriments(client, db, foods):
    h = _auth(db)
    r = client.get(f"{BASE}/foods/search", headers=h, params={"q": "hide"})
    hit = r.json()["results"][0]
    assert hit["kind"] == "packaged"
    assert hit["brand"] == "Parle"
    assert hit["nutriments"]["energy_kcal_100g"] == 479.0


def test_matches_on_brand_too(client, db, foods):
    h = _auth(db)
    r = client.get(f"{BASE}/foods/search", headers=h, params={"q": "sunfeast"})
    names = {d["name"] for d in r.json()["results"]}
    assert names == {"Dark Fantasy Bourbon"}


def test_short_query_is_rejected(client, db, foods):
    h = _auth(db)
    assert client.get(f"{BASE}/foods/search", headers=h,
                      params={"q": "p"}).status_code == 422


def test_like_wildcards_are_literal(client, db, foods):
    h = _auth(db)
    r = client.get(f"{BASE}/foods/search", headers=h, params={"q": "po%ha"})
    assert r.status_code == 200
    assert r.json()["results"] == []


def test_empty_catalog_is_not_an_error(client, db):
    h = _auth(db)
    r = client.get(f"{BASE}/foods/search", headers=h, params={"q": "poha"})
    assert r.status_code == 200
    assert r.json() == {"query": "poha", "results": []}
