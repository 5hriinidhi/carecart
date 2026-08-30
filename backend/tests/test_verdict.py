"""Phase 4.4 - food-drug interaction & severity scoring.

Loads the real reference CSVs once (also exercising the extended
``scripts.load_risk_tables.load_all``), then checks the deduction model, the
exact Phase 2.1 tier thresholds, the allergen hard-stop, and the endpoint.
"""

from __future__ import annotations

import datetime as dt

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import (
    Allergy,
    AuditLog,
    Condition,
    LifestyleProfile,
    Medication,
    User,
)
from app.services import verdict as V
from app.services.ingredient_risk import resolve_ingredients
from scripts.load_risk_tables import load_all


@pytest.fixture(scope="module", autouse=True)
def _ref_data(engine):
    with Session(engine) as s:
        counts = load_all(s, settings.risk_data_path)
    assert counts["interaction_rules"] > 50
    assert counts["drug_class_lookup"] > 500
    assert counts["allergen_aliases"] > 20
    yield


@pytest.fixture
def user(db) -> User:
    u = User(phone_hash=hash_phone("+919444100001"))
    db.add(u)
    db.flush()
    return u


@pytest.fixture
def auth(user) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _score(db, ingredients, *, conditions=(), allergies=(), medications=(),
           nutriments=None, lifestyle_scores=None):
    res = resolve_ingredients(db, list(ingredients), nutriments=nutriments or {},
                              queue_unresolved=False)
    return V.score_verdict(
        db, resolution=res, conditions=list(conditions), allergies=list(allergies),
        medications=list(medications), nutriments=nutriments or {},
        lifestyle_scores=lifestyle_scores,
    )


# ------------------------------------------------------------------ tiers (2.1)
@pytest.mark.parametrize(
    "score,tier",
    [(100, "safe"), (70, "safe"), (69, "caution"), (45, "caution"), (44, "avoid"), (0, "avoid")],
)
def test_tier_thresholds_match_phase_2_1(score, tier):
    assert V.tier_for(score) == tier


# ------------------------------------------------------------- drug-class mapping
@pytest.mark.parametrize(
    "name,expected",
    [
        ("Warfarin 5mg", "Anticoagulant (vitamin K antagonist)"),
        ("Telmisartan 40 mg tablet", "Angiotensin receptor blocker (ARB)"),
        ("ramipril", "ACE inhibitor"),
        ("lithium carbonate", "Mood stabiliser"),
        ("omeprazole 20mg capsule", "Proton pump inhibitor"),  # via -prazole stem
    ],
)
def test_drug_class_resolution(db, name, expected):
    rules = V._load_rules(db)
    assert expected in V._drug_classes_for(name, rules)


def test_unknown_drug_is_not_identified(db):
    rules = V._load_rules(db)
    assert V._drug_classes_for("Zibblewockzine XR", rules) == []


# ------------------------------------------------------------------- clean case
def test_clean_product_scores_100_safe(db):
    v = _score(db, ["Rolled oats", "Water"])
    assert v.score == 100
    assert v.tier == "safe"
    assert v.hard_stop is False
    assert [r.kind for r in v.reasons] == ["clear"]


# --------------------------------------------------------------- allergen hard stop
def test_allergen_match_is_a_hard_stop_regardless_of_score(db):
    v = _score(db, ["Cashew nuts", "Sugar"], allergies=["Peanuts"])
    assert v.hard_stop is True
    assert v.tier == "avoid"
    assert v.score == 0
    top = v.reasons[0]
    assert top.kind == "allergen"
    assert top.points == 0  # a stop, not a deduction
    assert "allergic to Peanuts" in top.title


def test_no_allergy_stored_means_no_hard_stop(db):
    v = _score(db, ["Cashew nuts"])
    assert v.hard_stop is False
    assert v.tier != "avoid" or v.score > 0


# -------------------------------------------------- proposal interaction examples
def test_warfarin_vitamin_k_interaction(db):
    v = _score(db, ["Broccoli", "Water"], medications=["Warfarin 5mg"])
    r = next(r for r in v.reasons if r.kind == "drug_interaction")
    assert "Vitamin K" in r.title
    assert r.severity == "high"
    assert r.points == 35
    assert v.score == 65
    assert v.tier == "caution"


def test_lithium_sodium_interaction(db):
    v = _score(db, ["Iodised salt", "Wheat flour"], medications=["Lithium carbonate 300mg"])
    kinds = {r.kind for r in v.reasons}
    assert "drug_interaction" in kinds
    r = next(r for r in v.reasons if r.kind == "drug_interaction")
    assert "sodium" in r.title.lower()
    assert r.points == 35  # HIGH


# ---------------------------------------------------------- condition rules
def test_condition_nutrient_ceiling_exceeded(db):
    v = _score(db, ["Wheat flour"], conditions=["Hypertension"],
               nutriments={"sodium_mg_100g": 1200})
    ceil = next(r for r in v.reasons if r.kind == "condition_ceiling")
    assert "sodium" in ceil.title.lower()
    assert ceil.points >= 25
    # the same sodium must not also be double-counted as general poor-fit
    assert not any(r.kind == "poor_fit" and "odium" in r.title for r in v.reasons)


def test_condition_ceiling_not_triggered_below_limit(db):
    v = _score(db, ["Wheat flour"], conditions=["Hypertension"],
               nutriments={"sodium_mg_100g": 100})
    assert not any(r.kind == "condition_ceiling" for r in v.reasons)


def test_condition_risk_compound_without_nutriments(db):
    v = _score(db, ["Chicken liver", "Salt"], conditions=["Gout"])
    r = next(r for r in v.reasons if r.kind == "condition_compound")
    assert "purine" in r.title.lower()
    assert r.severity == "high"
    assert r.points == 28


# ------------------------------------------------------------------ unverified
def test_unverified_ingredient_lowers_the_score_and_is_listed(db):
    v = _score(db, ["Zorblax crystalline extract", "Water"])
    r = next(r for r in v.reasons if r.kind == "unverified" and r.points > 0)
    assert r.points == 4
    assert v.score == 96
    assert v.unverified == ["zorblax crystalline extract"]


# --------------------------------------------------------- deduction stacking / tiers
def test_stacked_high_interactions_reach_avoid(db):
    # warfarin x vitamin K (broccoli) + lithium x sodium (salt) = -35 -35
    v = _score(db, ["Broccoli", "Iodised salt"],
               medications=["Warfarin", "Lithium carbonate"])
    assert v.score == 30
    assert v.tier == "avoid"
    assert v.hard_stop is False  # avoid by score, not a hard stop


def test_single_moderate_interaction_stays_safe(db):
    # ACE inhibitor x sodium is MODERATE (-20) -> 80
    v = _score(db, ["Iodised salt", "Wheat flour"], medications=["Ramipril 5mg"])
    r = next(r for r in v.reasons if r.kind == "drug_interaction")
    assert r.points == 20
    assert v.score == 80 and v.tier == "safe"


# ---------------------------------------------------- 7b: lifestyle multipliers
def test_poor_stress_amplifies_an_added_sugar_deduction(db):
    base = _score(db, ["Sugar", "Water"])
    poor = next(r for r in base.reasons if r.kind == "poor_fit")
    assert poor.factor == "added_sugar" and poor.points == 6
    assert base.lifestyle_applied == []

    # stress 22/100 (< 35) -> x1.25 -> 6 -> 8
    hi = _score(db, ["Sugar", "Water"], lifestyle_scores={"stress": 22})
    poor2 = next(r for r in hi.reasons if r.kind == "poor_fit")
    assert poor2.points == 8
    assert hi.score == base.score - 2
    assert hi.lifestyle_applied == ["stress 22/100 ×1.25 on added_sugar"]

    # a moderate stress score (>= 50) changes nothing
    ok = _score(db, ["Sugar", "Water"], lifestyle_scores={"stress": 80})
    assert next(r for r in ok.reasons if r.kind == "poor_fit").points == 6
    assert ok.lifestyle_applied == []


def test_lifestyle_never_touches_allergens_or_drug_interactions(db):
    # allergen hard stop: score 0 regardless
    v = _score(db, ["Peanuts", "Sugar"], allergies=["Peanut"],
               lifestyle_scores={"stress": 10, "exercise": 10})
    assert v.hard_stop and v.score == 0

    # a drug-interaction deduction is not scaled (no amplifier maps to it)
    v2 = _score(db, ["Iodised salt", "Wheat flour"], medications=["Ramipril 5mg"],
                lifestyle_scores={"exercise": 10, "stress": 10})
    assert next(r for r in v2.reasons if r.kind == "drug_interaction").points == 20
    assert v2.lifestyle_applied == []


def test_unanswered_lifestyle_dimension_is_a_no_op(db):
    # stress not in the map -> no multiplier even though exercise is terrible
    v = _score(db, ["Sugar", "Water"], lifestyle_scores={"exercise": 10})
    assert next(r for r in v.reasons if r.kind == "poor_fit").points == 6
    assert v.lifestyle_applied == []


def test_endpoint_returns_lifestyle_applied(client, db, user, auth):
    db.add(LifestyleProfile(user_id=user.id, data={"stress": 5}))  # -> score 22
    db.flush()
    r = client.post(
        "/api/v1/scan/verdict",
        headers=auth,
        json={"ingredients": ["Sugar", "Water"], "nutriments": {}},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["lifestyle_applied"] == ["stress 22/100 ×1.25 on added_sugar"]


# ------------------------------------------------------------------- endpoint
def _add_vault(db, user, *, conditions=(), allergies=(), meds=()):
    for c in conditions:
        db.add(Condition(user_id=user.id, condition_name=c))
    for a in allergies:
        db.add(Allergy(user_id=user.id, allergen_name=a))
    for m in meds:
        db.add(Medication(user_id=user.id, name=m))
    db.flush()


def test_endpoint_scores_against_the_stored_vault(client, db, user, auth):
    _add_vault(db, user, conditions=["Hypertension"], meds=["Warfarin 5mg"])
    r = client.post(
        "/api/v1/scan/verdict",
        headers=auth,
        json={
            "ingredients": ["Broccoli", "Iodised salt"],
            "nutriments": {"sodium_mg_100g": 1300},
            "product_name": "Green mix",
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["tier"] == "avoid"
    assert body["score"] < 45
    kinds = {x["kind"] for x in body["reasons"]}
    assert {"drug_interaction", "condition_ceiling"} <= kinds
    assert body["medications"][0]["identified"] is True
    assert "Anticoagulant (vitamin K antagonist)" in body["medications"][0]["drug_classes"]


def test_endpoint_allergen_hard_stop(client, db, user, auth):
    _add_vault(db, user, allergies=["tree nuts"])
    r = client.post(
        "/api/v1/scan/verdict",
        headers=auth,
        json={"ingredients": ["Roasted cashew", "Sugar"], "nutriments": {}},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["hard_stop"] is True
    assert body["tier"] == "avoid"
    assert body["score"] == 0
    assert body["reasons"][0]["kind"] == "allergen"


def test_endpoint_writes_an_audit_row(client, db, user, auth):
    client.post(
        "/api/v1/scan/verdict",
        headers=auth,
        json={"ingredients": ["Oats"], "nutriments": {}},
    )
    rows = db.scalars(
        select(AuditLog).where(AuditLog.user_id == user.id,
                               AuditLog.resource == "scan_verdict")
    ).all()
    assert len(rows) == 1
    assert rows[0].action == "read"


def test_endpoint_ignores_inactive_medications(client, db, user, auth):
    yesterday = dt.date.today() - dt.timedelta(days=1)
    db.add(Medication(user_id=user.id, name="Warfarin", active_to=yesterday))
    db.flush()
    r = client.post(
        "/api/v1/scan/verdict",
        headers=auth,
        json={"ingredients": ["Broccoli"], "nutriments": {}},
    )
    body = r.json()
    assert not any(x["kind"] == "drug_interaction" for x in body["reasons"])
    assert body["medications"] == []  # inactive med not even listed


def test_endpoint_requires_auth(client):
    r = client.post("/api/v1/scan/verdict", json={"ingredients": ["salt"]})
    assert r.status_code == 401
