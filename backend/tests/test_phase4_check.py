"""Phase 4 Check - a real scan produces a trustworthy verdict, end to end.

Drives the actual route chain a barcode scan goes through:
    GET  /api/v1/products/{barcode}     (Open Food Facts lookup, here mocked)
    POST /api/v1/scan/verdict           (4.3 resolve + 4.4 score, all real)

against a test user with a known condition / allergy / medication set (Phase 3),
and checks the result carries the correct tier + score and a reason that NAMES
the actual conflict - not a generic message. Also times the in-process round
trip.

`CARECART_LIVE_OFF=1 pytest tests/test_phase4_check.py -s` additionally runs the
timing case against the *real* Open Food Facts API.

Run:  pytest tests/test_phase4_check.py -v -s
"""

from __future__ import annotations

import os
import time

import pytest
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import Allergy, Condition, Medication, User
from scripts.load_risk_tables import load_all

CONFLICT_BARCODE = "8901491100014"   # real-format EAN; OFF response mocked below
CLEAN_BARCODE = "3017620422003"
PEANUT_BARCODE = "0037600106672"

# --- mocked Open Food Facts payloads (raw OFF shape; normalise() converts) ---
_OFF_GREENS_SEV = {
    "code": CONFLICT_BARCODE,
    "product_name": "Palak Methi Multigrain Sev",
    "brands": "Test Foods",
    "ingredients_text": "Gram flour, spinach, fenugreek leaves, iodised salt, "
    "edible vegetable oil, spices",
    "ingredients": [
        {"text": "Gram flour"},
        {"text": "Spinach"},
        {"text": "Fenugreek leaves"},
        {"text": "Iodised salt"},
        {"text": "Edible vegetable oil"},
        {"text": "Spices"},
    ],
    "nutriments": {
        "energy-kcal_100g": 520,
        "sodium_100g": 1.18,          # -> 1180 mg / 100 g
        "salt_100g": 2.95,
        "saturated-fat_100g": 4.2,
        "fat_100g": 30,
        "sugars_100g": 2,
        "carbohydrates_100g": 45,
    },
    "serving_size": "30 g",
}
_OFF_OATS = {
    "code": CLEAN_BARCODE,
    "product_name": "Rolled Oats",
    "brands": "Quaker",
    "ingredients_text": "Rolled oats",
    "ingredients": [{"text": "Rolled oats"}],
    "nutriments": {
        "energy-kcal_100g": 379,
        "sugars_100g": 1.0,
        "sodium_100g": 0.004,
        "salt_100g": 0.01,
        "saturated-fat_100g": 1.3,
        "fiber_100g": 10.0,
        "proteins_100g": 13.0,
    },
    "serving_size": "40 g",
}
_OFF_PEANUT_BUTTER = {
    "code": PEANUT_BARCODE,
    "product_name": "Creamy Peanut Butter",
    "brands": "Test Foods",
    "ingredients_text": "Roasted peanuts, sugar, palm oil, salt",
    "ingredients": [
        {"text": "Roasted peanuts"},
        {"text": "Sugar"},
        {"text": "Palm oil"},
        {"text": "Salt"},
    ],
    "nutriments": {"sugars_100g": 9.0, "sodium_100g": 0.4, "saturated-fat_100g": 8.0},
    "serving_size": "32 g",
}


@pytest.fixture(scope="module", autouse=True)
def _ref_data(engine):
    with Session(engine) as s:
        load_all(s, settings.risk_data_path)
    yield


@pytest.fixture
def user(db) -> User:
    """Known Phase 3 vault: Hypertension, Peanut allergy, Warfarin."""
    u = User(phone_hash=hash_phone("+919666100001"))
    db.add(u)
    db.flush()
    db.add(Condition(user_id=u.id, condition_name="Hypertension"))
    db.add(Allergy(user_id=u.id, allergen_name="Peanuts"))
    db.add(Medication(user_id=u.id, name="Warfarin 5mg"))
    db.flush()
    return u


@pytest.fixture
def auth(user) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _scan(client, auth, barcode) -> tuple[dict, dict, float]:
    """Full round trip: GET product -> POST verdict. Returns (product, verdict, ms)."""
    t0 = time.perf_counter()
    pr = client.get(f"/api/v1/products/{barcode}", headers=auth)
    assert pr.status_code == 200, pr.text
    product = pr.json()
    vr = client.post(
        "/api/v1/scan/verdict",
        headers=auth,
        json={
            "ingredients": product["ingredients"],
            "nutriments": product["nutriments"],
            "barcode": barcode,
            "product_name": product["name"],
        },
    )
    assert vr.status_code == 200, vr.text
    ms = (time.perf_counter() - t0) * 1000
    return product, vr.json(), ms


def _dump(tag, product, verdict, ms):
    print(f"\n===== {tag} =====")
    print(f"product: {product['name']} ({product['brand']}) - "
          f"{len(product['ingredients'])} ingredients, nutriments={product['nutriments']}")
    print(f"score={verdict['score']}  tier={verdict['tier']}  hard_stop={verdict['hard_stop']}")
    for r in verdict["reasons"]:
        print(f"  [{r['kind']}/{r['severity']} -{r['points']}] {r['title']}")
        if r["detail"]:
            print(f"      {r['detail']}")
    print(f"round trip (GET product + POST verdict, in-process): {ms:.0f} ms")


# --------------------------------------------------------------------------- #
def test_conflict_product_gives_avoid_with_a_specific_reason(client, auth, monkeypatch):
    monkeypatch.setattr(
        "app.services.openfoodfacts.fetch_product", lambda bc: _OFF_GREENS_SEV
    )
    product, verdict, ms = _scan(client, auth, CONFLICT_BARCODE)
    _dump("CASE 1 - product that conflicts (greens = vitamin K; 1180 mg sodium)",
          product, verdict, ms)

    # product decoded correctly
    assert product["nutriments"]["sodium_mg_100g"] == pytest.approx(1180, abs=1)

    # verdict tier matches the score on the Phase 2.1 thresholds
    assert verdict["score"] < 45
    assert verdict["tier"] == "avoid"

    titles = " || ".join(r["title"] for r in verdict["reasons"])
    details = " || ".join(r["detail"] or "" for r in verdict["reasons"])

    # a reason that NAMES the real conflict - the drug and the compound
    assert "Warfarin 5mg" in titles
    assert "Vitamin K" in titles
    # and the condition-specific ceiling, with the actual numbers
    assert "High sodium for Hypertension" in titles
    assert "1180" in details and "500 per-100 g limit" in details

    # NOT a generic catch-all
    for generic in ("may not be suitable", "please review", "could be a concern",
                    "generic", "review this product"):
        assert generic.lower() not in titles.lower()

    kinds = {r["kind"] for r in verdict["reasons"]}
    assert "drug_interaction" in kinds and "condition_ceiling" in kinds
    assert verdict["medications"][0]["identified"] is True


def test_allergen_product_is_a_hard_avoid_regardless(client, auth, monkeypatch):
    monkeypatch.setattr(
        "app.services.openfoodfacts.fetch_product", lambda bc: _OFF_PEANUT_BUTTER
    )
    product, verdict, ms = _scan(client, auth, PEANUT_BARCODE)
    _dump("CASE 2 - product with the user's allergen (peanuts)", product, verdict, ms)

    assert verdict["hard_stop"] is True
    assert verdict["tier"] == "avoid"
    assert verdict["score"] == 0
    top = verdict["reasons"][0]
    assert top["kind"] == "allergen" and top["points"] == 0
    assert "Peanuts" in top["title"]


def test_clean_product_gives_a_safe_verdict(client, auth, monkeypatch):
    monkeypatch.setattr(
        "app.services.openfoodfacts.fetch_product", lambda bc: _OFF_OATS
    )
    product, verdict, ms = _scan(client, auth, CLEAN_BARCODE)
    _dump("CASE 3 - product with no conflicts (rolled oats)", product, verdict, ms)

    assert verdict["score"] >= 70
    assert verdict["tier"] == "safe"
    assert verdict["hard_stop"] is False
    # no drug / condition / allergen conflict was raised
    conflict_kinds = {"allergen", "drug_interaction", "condition_ceiling", "condition_compound"}
    assert not (conflict_kinds & {r["kind"] for r in verdict["reasons"]})
    assert any("No conflicts found" in r["title"] for r in verdict["reasons"])


def test_round_trip_is_comfortably_under_a_few_seconds(client, auth, monkeypatch):
    # simulate a realistic Open Food Facts latency on the (uncached) first call
    def _slow_off(bc):
        time.sleep(0.4)
        return _OFF_GREENS_SEV

    monkeypatch.setattr("app.services.openfoodfacts.fetch_product", _slow_off)
    _, verdict, ms = _scan(client, auth, CONFLICT_BARCODE)
    print(f"\nCASE 4 - round trip with ~400 ms simulated OFF latency: {ms:.0f} ms")
    assert ms < 3000, f"round trip took {ms:.0f} ms"
    # second scan of the same barcode: OFF is cached, so it must be much faster
    _, _, ms2 = _scan(client, auth, CONFLICT_BARCODE)
    print(f"        second scan (product cached): {ms2:.0f} ms")
    assert ms2 < ms


@pytest.mark.skipif(
    os.getenv("CARECART_LIVE_OFF") != "1",
    reason="set CARECART_LIVE_OFF=1 to hit the real Open Food Facts API",
)
def test_live_off_round_trip_timing(client, auth):
    """Real GET (Open Food Facts) + real POST verdict, timed. Nutella = a real
    barcode OFF definitely has, with full nutriments."""
    _, verdict, ms = _scan(client, auth, "3017620422003")
    print(f"\nLIVE - real OFF fetch + verdict, cold: {ms:.0f} ms  tier={verdict['tier']}")
    _, _, ms2 = _scan(client, auth, "3017620422003")
    print(f"LIVE - second scan (cached): {ms2:.0f} ms")
    assert ms < 5000
