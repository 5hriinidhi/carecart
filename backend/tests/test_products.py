"""Phase 4.1 - GET /products/{barcode}: Open Food Facts lookup + 24h Postgres cache."""

from __future__ import annotations

import httpx
import pytest
from sqlalchemy import text

from app.core.security import create_access_token, hash_phone
from app.models import User
from app.services import openfoodfacts

BARCODE = "3017620422003"
URL = f"/api/v1/products/{BARCODE}"

_OFF_PRODUCT = {
    "code": BARCODE,
    "product_name": "Nutella",
    "brands": "Ferrero,Nutella",
    "ingredients_text": "Sugar, palm oil, hazelnuts 13%, skimmed milk powder, cocoa",
    "ingredients": [
        {"id": "en:sugar", "text": "Sugar"},
        {"id": "en:palm-oil", "text": "Palm oil"},
        {"id": "en:hazelnut", "text": "Hazelnuts", "percent": 13},
        {"id": "en:skimmed-milk-powder", "text": "Skimmed milk powder"},
        {"id": "en:cocoa", "text": "Cocoa"},
    ],
    "nutriments": {
        "energy-kcal_100g": 539,
        "sugars_100g": 56.3,
        "salt_100g": 0.107,
        "sodium_100g": 0.0428,
        "saturated-fat_100g": 10.6,
        "fat_100g": 30.9,
        "proteins_100g": 6.3,
        "carbohydrates_100g": 57.5,
        "fiber_100g": 0,
    },
    "serving_size": "15 g",
    "image_front_small_url": "https://images.openfoodfacts.org/x/front_small.jpg",
    "quantity": "400 g",
}


@pytest.fixture
def auth(db) -> dict:
    user = User(phone_hash=hash_phone("+919444000001"))
    db.add(user)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _mock_fetch(monkeypatch, value):
    calls = {"n": 0}

    def _fake(barcode):
        calls["n"] += 1
        if isinstance(value, Exception):
            raise value
        return value

    monkeypatch.setattr("app.services.openfoodfacts.fetch_product", _fake)
    return calls


def _forbid_fetch(monkeypatch):
    def _boom(_barcode):
        raise AssertionError("Open Food Facts was called when the cache should have served it")

    monkeypatch.setattr("app.services.openfoodfacts.fetch_product", _boom)


def _age_row(db, barcode: str, hours: int = 25):
    db.execute(
        text("UPDATE products SET refreshed_at = now() - make_interval(hours => :h) "
             "WHERE barcode = :b"),
        {"h": hours, "b": barcode},
    )
    db.flush()


# ------------------------------------------------------------------ found path --
def test_lookup_found_is_normalized_and_cached(client, db, auth, monkeypatch):
    _mock_fetch(monkeypatch, _OFF_PRODUCT)

    r = client.get(URL, headers=auth)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["barcode"] == BARCODE
    assert body["name"] == "Nutella"
    assert body["brand"] == "Ferrero"
    assert body["ingredients"] == [
        "Sugar", "Palm oil", "Hazelnuts", "Skimmed milk powder", "Cocoa"
    ]
    assert body["nutriments"]["sugars_g_100g"] == 56.3
    assert body["nutriments"]["sodium_mg_100g"] == 42.8  # 0.0428 g -> 42.8 mg
    assert body["serving_size"] == "15 g"
    assert body["cached"] is False and body["stale"] is False

    row = db.execute(
        text(
            "SELECT off_status, name, raw IS NOT NULL AS has_raw "
            "FROM products WHERE barcode = :b"
        ),
        {"b": BARCODE},
    ).one()
    assert row.off_status == "found" and row.name == "Nutella" and row.has_raw


def test_second_lookup_served_from_cache_without_calling_off(client, auth, monkeypatch):
    _mock_fetch(monkeypatch, _OFF_PRODUCT)
    assert client.get(URL, headers=auth).status_code == 200

    _forbid_fetch(monkeypatch)
    r = client.get(URL, headers=auth)
    assert r.status_code == 200
    assert r.json()["cached"] is True
    assert r.json()["name"] == "Nutella"


def test_cache_refetches_after_ttl(client, db, auth, monkeypatch):
    _mock_fetch(monkeypatch, _OFF_PRODUCT)
    client.get(URL, headers=auth)
    _age_row(db, BARCODE, hours=25)

    updated = {**_OFF_PRODUCT, "product_name": "Nutella (new recipe)"}
    calls = _mock_fetch(monkeypatch, updated)
    r = client.get(URL, headers=auth)
    assert calls["n"] == 1
    assert r.json()["name"] == "Nutella (new recipe)"
    assert r.json()["cached"] is False


# --------------------------------------------------------------- not-found path --
def test_not_found_returns_404_with_ocr_fallback(client, db, auth, monkeypatch):
    _mock_fetch(monkeypatch, None)

    r = client.get(URL, headers=auth)
    assert r.status_code == 404
    body = r.json()
    assert body["fallback"] == "ocr"
    assert body["barcode"] == BARCODE
    assert body["detail"]

    status_ = db.execute(
        text("SELECT off_status FROM products WHERE barcode = :b"), {"b": BARCODE}
    ).scalar_one()
    assert status_ == "not_found"


def test_negative_result_is_cached(client, auth, monkeypatch):
    _mock_fetch(monkeypatch, None)
    assert client.get(URL, headers=auth).status_code == 404

    _forbid_fetch(monkeypatch)
    r = client.get(URL, headers=auth)
    assert r.status_code == 404 and r.json()["fallback"] == "ocr"


def test_negative_cache_also_expires(client, db, auth, monkeypatch):
    _mock_fetch(monkeypatch, None)
    client.get(URL, headers=auth)
    _age_row(db, BARCODE, hours=25)

    calls = _mock_fetch(monkeypatch, _OFF_PRODUCT)  # now OFF has it
    r = client.get(URL, headers=auth)
    assert calls["n"] == 1
    assert r.status_code == 200 and r.json()["name"] == "Nutella"


# ------------------------------------------------------------------- guards --
@pytest.mark.parametrize("bad", ["abc", "12345", "1234567", "123456789012345", "12-34-56"])
def test_invalid_barcode_is_422(client, auth, bad):
    assert client.get(f"/api/v1/products/{bad}", headers=auth).status_code == 422


def test_requires_a_jwt(client):
    assert client.get(URL).status_code == 401


# ------------------------------------------------------- upstream failure --
def test_upstream_error_serves_stale_found_cache(client, db, auth, monkeypatch):
    _mock_fetch(monkeypatch, _OFF_PRODUCT)
    client.get(URL, headers=auth)
    _age_row(db, BARCODE, hours=48)

    _mock_fetch(monkeypatch, openfoodfacts.OpenFoodFactsError("down"))
    r = client.get(URL, headers=auth)
    assert r.status_code == 200
    assert r.json()["stale"] is True
    assert r.json()["cached"] is True
    assert r.json()["name"] == "Nutella"


def test_upstream_error_without_cache_is_502(client, auth, monkeypatch):
    _mock_fetch(monkeypatch, openfoodfacts.OpenFoodFactsError("down"))
    r = client.get(URL, headers=auth)
    assert r.status_code == 502
    assert "ingredients" in r.json()["detail"].lower()


# ------------------------------------------------------- normalize() unit --
def test_normalize_converts_sodium_and_reads_structured_ingredients():
    n = openfoodfacts.normalize(BARCODE, _OFF_PRODUCT)
    assert n.name == "Nutella"
    assert n.brand == "Ferrero"
    assert n.ingredients[:2] == ["Sugar", "Palm oil"]
    assert n.nutriments["sodium_mg_100g"] == 42.8
    assert n.nutriments["energy_kcal_100g"] == 539.0


def test_normalize_falls_back_to_ingredients_text():
    p = {"product_name": "X", "ingredients_text": "water; sugar, salt."}
    n = openfoodfacts.normalize("00000000", p)
    assert n.ingredients == ["water", "sugar", "salt"]


def test_normalize_handles_an_empty_product():
    n = openfoodfacts.normalize("00000000", {})
    assert n.name is None and n.brand is None
    assert n.ingredients == [] and n.nutriments == {}


# ------------------------------------------------------- fetch_product() unit --
def _resp(url, status_code, payload=None):
    return httpx.Response(status_code, json=payload, request=httpx.Request("GET", url))


def test_fetch_product_status_zero_is_none(monkeypatch):
    monkeypatch.setattr(
        "app.services.openfoodfacts.httpx.get",
        lambda url, **_kw: _resp(url, 200, {"status": 0, "status_verbose": "not found"}),
    )
    assert openfoodfacts.fetch_product("0000000000000") is None


def test_fetch_product_http_404_is_none(monkeypatch):
    monkeypatch.setattr(
        "app.services.openfoodfacts.httpx.get", lambda url, **_kw: _resp(url, 404, {})
    )
    assert openfoodfacts.fetch_product("0000000000000") is None


def test_fetch_product_5xx_raises(monkeypatch):
    monkeypatch.setattr(
        "app.services.openfoodfacts.httpx.get", lambda url, **_kw: _resp(url, 503, {})
    )
    with pytest.raises(openfoodfacts.OpenFoodFactsError):
        openfoodfacts.fetch_product("0000000000000")


def test_fetch_product_network_error_raises(monkeypatch):
    def _boom(url, **_kw):
        raise httpx.ConnectError("no route to host")

    monkeypatch.setattr("app.services.openfoodfacts.httpx.get", _boom)
    with pytest.raises(openfoodfacts.OpenFoodFactsError):
        openfoodfacts.fetch_product("0000000000000")


def test_fetch_product_sends_a_user_agent(monkeypatch):
    seen = {}

    def _capture(url, **kw):
        seen.update(kw.get("headers", {}))
        return _resp(url, 200, {"status": 1, "product": _OFF_PRODUCT})

    monkeypatch.setattr("app.services.openfoodfacts.httpx.get", _capture)
    openfoodfacts.fetch_product(BARCODE)
    assert "CareCart" in seen.get("User-Agent", "")
