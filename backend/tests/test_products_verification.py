"""Phase 4.1 verification - the three scenarios from the verification prompt.

  1. a real, known barcode: correct data, and the SECOND call is a cache hit
     (X-Cache header + call count + response time) - Open Food Facts is not
     contacted again.
  2. a made-up / invalid barcode: a clean 404 with the fallback flag.
  3. Open Food Facts unreachable (simulated timeout): a graceful error, never a
     hang or a 500.

Run:  pytest tests/test_products_verification.py -v -s
"""

from __future__ import annotations

import time

import httpx
import pytest
from sqlalchemy import text

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import User
from app.services import openfoodfacts

# 5000159407236 = a real Coca-Cola can barcode; we mock OFF's response for it.
BARCODE = "5000159407236"
URL = f"/api/v1/products/{BARCODE}"

_OFF_COKE = {
    "code": BARCODE,
    "product_name": "Coca-Cola",
    "brands": "Coca-Cola",
    "ingredients_text": "Carbonated water, sugar, colour (caramel E150d), "
    "phosphoric acid, natural flavourings including caffeine",
    "ingredients": [
        {"id": "en:carbonated-water", "text": "Carbonated water"},
        {"id": "en:sugar", "text": "Sugar"},
        {"id": "en:colour", "text": "Colour"},
        {"id": "en:phosphoric-acid", "text": "Phosphoric acid"},
        {"id": "en:natural-flavouring", "text": "Natural flavourings"},
    ],
    "nutriments": {
        "energy-kcal_100g": 42,
        "sugars_100g": 10.6,
        "salt_100g": 0.0,
        "sodium_100g": 0.0,
        "fat_100g": 0.0,
        "proteins_100g": 0.0,
        "carbohydrates_100g": 10.6,
    },
    "serving_size": "330 ml",
    "image_front_small_url": "https://images.openfoodfacts.org/coke_small.jpg",
}


@pytest.fixture
def auth(db) -> dict:
    user = User(phone_hash=hash_phone("+919777000001"))
    db.add(user)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


class _Off:
    """Stand-in for Open Food Facts. Records call count and simulates latency."""

    def __init__(self, *, result, latency_s: float = 0.20):
        self.result = result
        self.latency_s = latency_s
        self.calls = 0

    def __call__(self, barcode: str):
        self.calls += 1
        time.sleep(self.latency_s)
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


def _install(monkeypatch, off: _Off) -> _Off:
    monkeypatch.setattr("app.services.openfoodfacts.fetch_product", off)
    return off


def _age(db, barcode: str, hours: int = 25):
    db.execute(
        text("UPDATE products SET refreshed_at = now() - make_interval(hours => :h) "
             "WHERE barcode = :b"),
        {"h": hours, "b": barcode},
    )
    db.flush()


# ---------------------------------------------------------------------------
# 1. real known barcode -> correct data; 2nd call is a cache hit
# ---------------------------------------------------------------------------
def test_1_known_barcode_then_cache_hit(client, db, auth, monkeypatch):
    off = _install(monkeypatch, _Off(result=_OFF_COKE, latency_s=0.25))

    t0 = time.perf_counter()
    first = client.get(URL, headers=auth)
    miss_ms = (time.perf_counter() - t0) * 1000

    assert first.status_code == 200
    body = first.json()
    assert body["name"] == "Coca-Cola"
    assert body["brand"] == "Coca-Cola"
    assert body["ingredients"][:2] == ["Carbonated water", "Sugar"]
    assert body["nutriments"]["sugars_g_100g"] == 10.6
    assert body["serving_size"] == "330 ml"
    assert body["cached"] is False
    assert first.headers["X-Cache"] == "MISS"

    t0 = time.perf_counter()
    second = client.get(URL, headers=auth)
    hit_ms = (time.perf_counter() - t0) * 1000

    assert second.status_code == 200
    assert second.json()["name"] == "Coca-Cola"
    assert second.json()["cached"] is True
    assert second.headers["X-Cache"] == "HIT"

    # the definitive proof: Open Food Facts was hit exactly once
    assert off.calls == 1
    # ...and the cached call was much faster than the one that went upstream
    assert hit_ms < miss_ms
    print(
        f"[1] MISS {miss_ms:.0f} ms (X-Cache: MISS) -> "
        f"HIT {hit_ms:.0f} ms (X-Cache: HIT); OFF calls = {off.calls}"
    )

    stored = db.execute(
        text("SELECT off_status, name FROM products WHERE barcode = :b"), {"b": BARCODE}
    ).one()
    assert stored.off_status == "found" and stored.name == "Coca-Cola"


# ---------------------------------------------------------------------------
# 2. made-up / invalid barcode -> clean 404 + fallback flag
# ---------------------------------------------------------------------------
def test_2_made_up_barcode_is_clean_404_with_fallback(client, auth, monkeypatch):
    off = _install(monkeypatch, _Off(result=None))  # OFF has no such product

    r = client.get("/api/v1/products/9999999999999", headers=auth)
    assert r.status_code == 404
    body = r.json()
    assert body == {
        "detail": body["detail"],
        "barcode": "9999999999999",
        "fallback": "ocr",
    }
    assert body["fallback"] == "ocr"
    assert r.headers["X-Cache"] == "MISS"
    print(f"[2] made-up barcode -> 404 {body}")

    # negative result cached too -> second call doesn't re-hit OFF
    again = client.get("/api/v1/products/9999999999999", headers=auth)
    assert again.status_code == 404 and again.headers["X-Cache"] == "HIT"
    assert off.calls == 1


def test_2b_non_numeric_barcode_is_422(client, auth):
    r = client.get("/api/v1/products/not-a-barcode", headers=auth)
    assert r.status_code == 422
    print(f"[2b] 'not-a-barcode' -> {r.status_code} {r.json()['detail']!r}")


# ---------------------------------------------------------------------------
# 3. Open Food Facts unreachable -> graceful error, no hang, no 500
# ---------------------------------------------------------------------------
def test_3_off_unreachable_no_cache_returns_502_fast(client, auth, monkeypatch):
    err = openfoodfacts.OpenFoodFactsError("open food facts unreachable")
    _install(monkeypatch, _Off(result=err, latency_s=0.0))

    t0 = time.perf_counter()
    r = client.get(URL, headers=auth)
    elapsed = time.perf_counter() - t0

    assert r.status_code == 502  # graceful, not 500, not a hang
    assert "ingredients" in r.json()["detail"].lower()  # tells the client what to do
    assert elapsed < 2.0, "must fail fast, not hang"
    print(f"[3a] OFF down, no cache -> {r.status_code} in {elapsed * 1000:.0f} ms: "
          f"{r.json()['detail']!r}")


def test_3b_off_unreachable_serves_stale_cache(client, db, auth, monkeypatch):
    _install(monkeypatch, _Off(result=_OFF_COKE, latency_s=0.0))
    client.get(URL, headers=auth)            # warm the cache
    _age(db, BARCODE, hours=48)              # make it stale

    _install(monkeypatch, _Off(result=openfoodfacts.OpenFoodFactsError("down")))
    r = client.get(URL, headers=auth)
    assert r.status_code == 200
    assert r.json()["stale"] is True
    assert r.json()["name"] == "Coca-Cola"
    assert r.headers["X-Cache"] == "STALE"
    print("[3b] OFF down, stale cache present -> 200 X-Cache: STALE (served the old copy)")


def test_3c_a_real_timeout_maps_to_openfoodfactserror(monkeypatch):
    """fetch_product() turns an httpx timeout into OpenFoodFactsError - it never
    propagates a raw exception or blocks past httpx's own timeout."""
    def _timeout(url, **_kw):
        raise httpx.ReadTimeout("timed out", request=httpx.Request("GET", url))

    monkeypatch.setattr("app.services.openfoodfacts.httpx.get", _timeout)
    with pytest.raises(openfoodfacts.OpenFoodFactsError):
        openfoodfacts.fetch_product(BARCODE)

    # and the client is configured with a bounded timeout in the first place
    assert 0 < settings.off_timeout_seconds <= 15
    print(f"[3c] httpx.ReadTimeout -> OpenFoodFactsError; "
          f"off_timeout_seconds = {settings.off_timeout_seconds}")
