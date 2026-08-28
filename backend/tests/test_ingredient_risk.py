"""Phase 4.3 - offline ingredient -> risk_compound resolution.

Loads the real static reference CSVs into the test DB once (also exercising
``scripts.load_risk_tables.load_all``), then checks the resolver: keyword +
LLM-table + numeric-threshold matching, and that an unmatched ingredient is
marked ``unverified`` (never dropped, never treated as safe) and queued exactly
once per distinct text.
"""

from __future__ import annotations

import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import UnresolvedIngredient, User
from app.services import ingredient_risk
from app.services.ingredient_risk import clean_ingredient, resolve_ingredients
from scripts.load_risk_tables import load_all


@pytest.fixture(scope="module", autouse=True)
def _risk_data(engine):
    """Load the pre-built CSVs into the test DB once for this module."""
    with Session(engine) as s:
        counts = load_all(s, settings.risk_data_path)
    assert counts["risk_compounds"] >= 20
    assert counts["ingredient_risk_aliases"] > 300
    yield


@pytest.fixture
def auth(db) -> dict:
    user = User(phone_hash=hash_phone("+919333100001"))
    db.add(user)
    db.flush()
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


# --------------------------------------------------------------------- cleaning
@pytest.mark.parametrize(
    "raw,expected",
    [
        ("Sugar 20%", "sugar"),
        ("  Iodised Salt  ", "iodised salt"),
        ("Refined Wheat Flour", "refined wheat flour"),
        ("INS 500(ii)", None),          # E-number fragment -> nothing meaningful
        ("Emulsifier (INS 322)", None),  # additive prefix + number stripped
    ],
)
def test_clean_ingredient_strips_noise(raw, expected):
    out = clean_ingredient(raw)
    if expected is not None:
        assert out == expected
    else:
        # additive/number cases: no digits survive, prefix consumed
        assert not any(ch.isdigit() for ch in out)
        assert "emulsifier" not in out


# ------------------------------------------------------------------- keyword pass
def test_keyword_pass_tags_common_ingredients(db):
    res = resolve_ingredients(db, ["iodised salt", "sugar", "palm oil"])
    assert {i.method for i in res.ingredients} == {"keyword"}
    assert res.risk_compounds.get("sodium", 0) > 0
    assert res.risk_compounds.get("added_sugar", 0) > 0
    assert res.risk_compounds.get("saturated_fat", 0) > 0
    assert res.unverified == []
    assert res.caution_factors == []


def test_negation_suppresses_a_keyword_hit(db):
    res = resolve_ingredients(db, ["unsalted peanuts"])
    (peanuts,) = res.ingredients
    assert "nut_allergen" in peanuts.risk_compounds
    assert "sodium" not in peanuts.risk_compounds  # 'unsalted' negates the salt hit
    assert "sodium" not in res.risk_compounds


# ---------------------------------------------------------------- LLM-table pass
def test_llm_table_pass_matches_reviewed_tokens(db):
    res = resolve_ingredients(db, ["edible vegetable oil"])
    (oil,) = res.ingredients
    assert oil.method == "llm"
    assert oil.risk_compounds == ["saturated_fat"]
    assert oil.confidence == pytest.approx(0.4, abs=0.01)


def test_llm_reviewed_benign_token_is_not_unverified(db):
    # 'sunflower oil' is in llm_ingredient_tags.csv reviewed as carrying no compound
    res = resolve_ingredients(db, ["sunflower oil"])
    (row,) = res.ingredients
    assert row.method == "benign"
    assert row.risk_compounds == []
    assert res.unverified == []


# ------------------------------------------------------------- unverified + queue
def test_unmatched_ingredient_is_unverified_and_queued_once(db):
    token = "zorblax root distillate"
    res1 = resolve_ingredients(db, [token], sample_product="1234567890123")
    db.commit()

    (row,) = res1.ingredients
    assert row.method == "unverified"
    assert row.risk_compounds == []
    assert res1.unverified == ["zorblax root distillate"]
    assert res1.unverified_count == 1
    assert res1.caution_factors == ["We couldn't confirm 1 ingredient in this product."]
    # not silently added to the scored compounds
    assert "zorblax root distillate" not in res1.risk_compounds

    q = select(UnresolvedIngredient).where(
        UnresolvedIngredient.normalized_text == "zorblax root distillate"
    )
    queued = db.scalars(q).one()
    assert queued.times_seen == 1
    assert queued.status == "pending"
    assert queued.sample_product == "1234567890123"

    # seen again -> same row, times_seen bumped, no duplicate
    resolve_ingredients(db, [token], sample_product="9999999999999")
    db.commit()
    db.expire_all()  # Core upsert doesn't refresh the ORM identity map
    assert db.scalar(
        select(func.count()).select_from(UnresolvedIngredient).where(
            UnresolvedIngredient.normalized_text == "zorblax root distillate"
        )
    ) == 1
    assert db.scalars(q).one().times_seen == 2


def test_queue_write_can_be_disabled(db):
    res = resolve_ingredients(db, ["flibberjib crystals"], queue_unresolved=False)
    db.commit()
    assert res.ingredients[0].method == "unverified"
    assert db.scalar(select(func.count()).select_from(UnresolvedIngredient)) == 0


def test_plural_caution_wording(db):
    res = resolve_ingredients(db, ["wuzzle extract", "grumbo powder"])
    assert res.caution_factors == ["We couldn't confirm 2 ingredients in this product."]


# ------------------------------------------------------------- numeric thresholds
@pytest.mark.parametrize(
    "nutriments,expect_rc,expect_conf",
    [
        ({"sodium_mg_100g": 800}, "sodium", 0.8),
        ({"sodium_mg_100g": 200}, "sodium", 0.45),
        ({"sugars_g_100g": 30}, "added_sugar", 0.7),
        ({"saturated_fat_g_100g": 6}, "saturated_fat", 0.7),
    ],
)
def test_nutrient_thresholds_add_product_tags(db, nutriments, expect_rc, expect_conf):
    res = resolve_ingredients(db, [], nutriments=nutriments)
    tags = {t.risk_compound: t for t in res.product_tags}
    assert expect_rc in tags
    assert tags[expect_rc].method == "threshold"
    assert tags[expect_rc].confidence == pytest.approx(expect_conf, abs=0.01)
    assert res.risk_compounds[expect_rc] == pytest.approx(expect_conf, abs=0.01)


def test_nutrient_below_all_bands_adds_nothing(db):
    res = resolve_ingredients(db, [], nutriments={"sodium_mg_100g": 40})
    assert res.product_tags == []
    assert res.risk_compounds == {}


# ---------------------------------------------------------- offline guarantee
def test_resolver_never_makes_a_network_call(db, monkeypatch):
    import httpx

    def _boom(*a, **k):  # any outbound HTTP is a bug on the scan path
        raise AssertionError("ingredient_risk made a network call")

    monkeypatch.setattr(httpx, "get", _boom)
    monkeypatch.setattr(httpx, "post", _boom)
    res = resolve_ingredients(
        db, ["iodised salt", "totally novel biopolymer"],
        nutriments={"sugars_g_100g": 40},
    )
    db.commit()
    assert res.risk_compounds.get("sodium", 0) > 0
    assert res.unverified == ["totally novel biopolymer"]


def test_service_module_does_not_import_httpx():
    import inspect

    src = inspect.getsource(ingredient_risk)
    assert "httpx" not in src
    assert "anthropic" not in src


# ------------------------------------------------------------------- endpoint
def test_resolve_risks_endpoint(client, auth):
    r = client.post(
        "/api/v1/products/resolve-risks",
        headers=auth,
        json={
            "ingredients": ["Iodised salt", "sugar", "kryptonite seed extract"],
            "nutriments": {"saturated_fat_g_100g": 7},
            "barcode": "4901234567894",
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["risk_compounds"]["sodium"] > 0
    assert body["risk_compounds"]["added_sugar"] > 0
    assert body["risk_compounds"]["saturated_fat"] > 0  # from the threshold pass
    assert body["unverified"] == ["kryptonite seed extract"]
    assert body["unverified_count"] == 1
    assert body["caution_factors"] == [
        "We couldn't confirm 1 ingredient in this product."
    ]
    assert body["resolved_count"] == 2
    methods = {i["clean_text"]: i["method"] for i in body["ingredients"]}
    assert methods["kryptonite seed extract"] == "unverified"


def test_resolve_risks_requires_auth(client):
    r = client.post("/api/v1/products/resolve-risks", json={"ingredients": ["salt"]})
    assert r.status_code == 401
