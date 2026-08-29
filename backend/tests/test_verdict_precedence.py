"""Phase 4 edge cases - the documented precedence order + brand/generic matching.

Precedence (see app/services/verdict.py docstring):
  1. allergen match wins outright (score 0 / avoid / hard_stop)
  2. otherwise all factors stack additively, de-duped, clamped 0-100
  3. HIGH-severity floor: a HIGH clinical factor -> tier is at least "caution"
  4. reasons returned most-serious-first
"""

from __future__ import annotations

import pytest
from sqlalchemy.orm import Session

from app.core.config import settings
from app.services import verdict as V
from app.services.ingredient_risk import resolve_ingredients
from scripts.load_risk_tables import load_all


@pytest.fixture(scope="module", autouse=True)
def _ref(engine):
    with Session(engine) as s:
        counts = load_all(s, settings.risk_data_path)
    assert counts["drug_name_aliases"] > 40
    yield


def _v(db, ingredients, *, conditions=(), allergies=(), medications=(), nutriments=None):
    res = resolve_ingredients(db, list(ingredients), nutriments=nutriments or {},
                              queue_unresolved=False)
    return V.score_verdict(db, resolution=res, conditions=list(conditions),
                           allergies=list(allergies), medications=list(medications),
                           nutriments=nutriments or {})


# ---------------------------------------------------------- brand -> generic
@pytest.mark.parametrize(
    "brand,expected_class",
    [
        ("Ecosprin 75", "NSAID"),                            # aspirin
        ("Telma 40", "Angiotensin receptor blocker (ARB)"),  # telmisartan
        ("Glycomet 500", "Biguanide (antidiabetic)"),         # metformin
        ("Storvas 10", "Statin (HMG-CoA reductase inhibitor)"),  # atorvastatin
        ("Ciplox 500", "Fluoroquinolone"),                    # ciprofloxacin (via stem)
        ("Lithosun 300", "Mood stabiliser"),                  # lithium carbonate
    ],
)
def test_brand_names_resolve_to_a_drug_class(db, brand, expected_class):
    rules = V._load_rules(db)
    classes = V._drug_classes_for(brand, rules)
    assert expected_class in classes, f"{brand} -> {classes}"


def test_brand_name_makes_the_interaction_fire(db):
    # "Telma" alone would miss; via drug_name_aliases it is telmisartan (ARB),
    # and ARB x sodium is a MODERATE interaction.
    v = _v(db, ["Iodised salt", "Wheat flour"], medications=["Telma 40"])
    inter = [r for r in v.reasons if r.kind == "drug_interaction"]
    assert inter and "sodium" in inter[0].title.lower()
    assert v.medications[0].identified is True
    assert "Angiotensin receptor blocker (ARB)" in v.medications[0].drug_classes


def test_a_still_unknown_name_is_reported_not_silently_passed(db):
    v = _v(db, ["Broccoli"], medications=["Zibblewockz Forte"])
    assert v.medications[0].identified is False
    assert any(
        r.kind == "unverified" and "identify the drug class" in r.title
        for r in v.reasons
    )


# ------------------------------------------------------ 1. allergen wins outright
def test_allergen_beats_everything_else(db):
    # peanut allergen + two HIGH interactions in the same product
    v = _v(
        db,
        ["Groundnut", "Broccoli", "Iodised salt"],
        allergies=["Peanuts"],
        medications=["Warfarin", "Lithium carbonate"],
        nutriments={"sodium_mg_100g": 1500},
    )
    assert v.hard_stop is True
    assert v.tier == "avoid"
    assert v.score == 0
    assert v.reasons[0].kind == "allergen" and v.reasons[0].points == 0


# --------------------------------------------- 2. additive stacking + de-dup
def test_factors_stack_and_a_compound_is_never_counted_twice(db):
    # salt -> sodium: cited by the ACE interaction, so NOT also a poor-fit line;
    # and the sodium ceiling (mg) + salt ceiling (g) count once, not twice.
    v = _v(
        db,
        ["Iodised salt", "Sugar"],
        conditions=["Hypertension"],
        medications=["Ramipril 5mg"],
        nutriments={"sodium_mg_100g": 1300, "salt_g_100g": 3.25},
    )
    ceil = [r for r in v.reasons if r.kind == "condition_ceiling"]
    assert len(ceil) == 1  # one sodium/salt ceiling, not two
    assert not any(r.kind == "poor_fit" and "odium" in r.title for r in v.reasons)
    # interaction (-20) + one ceiling (-38) + added_sugar poor-fit (-6) = -64
    assert v.score == 36
    assert v.tier == "avoid"


# ------------------------------------------- 3. HIGH-severity floor
def test_high_severity_factor_floors_the_tier_at_caution(db):
    # gout + a pure high-purine ingredient: condition_compound HIGH is the only
    # deduction (-28) -> score 72, which is >= 70, but a HIGH clinical factor
    # means the verdict can't read "safe".
    v = _v(db, ["Liver"], conditions=["Gout"])
    assert [r.kind for r in v.reasons] == ["condition_compound"]
    assert v.reasons[0].severity == "high"
    assert v.score == 72
    assert v.tier == "caution"  # floored, not "safe"


def test_floor_does_not_apply_without_a_high_factor(db):
    # one MODERATE interaction (-20) -> 80, no HIGH factor -> stays safe
    v = _v(db, ["Iodised salt", "Wheat flour"], medications=["Ramipril 5mg"])
    assert all(r.severity != "high" for r in v.reasons)
    assert v.score == 80 and v.tier == "safe"


# --------------------------------------------- 4. reasons most-serious-first
def test_reasons_are_ordered_most_serious_first(db):
    v = _v(
        db,
        ["Groundnut", "Broccoli", "Iodised salt", "Sugar", "Zorblax powder"],
        allergies=["Peanuts"],
        conditions=["Hypertension", "Type 2 diabetes"],
        medications=["Warfarin"],
        nutriments={"sodium_mg_100g": 1100, "sugars_g_100g": 30},
    )
    order = {
        "allergen": 0, "drug_interaction": 1, "condition_ceiling": 2,
        "condition_compound": 3, "poor_fit": 4, "unverified": 5, "clear": 6,
    }
    ranks = [order[r.kind] for r in v.reasons]
    assert ranks == sorted(ranks)
    assert v.reasons[0].kind == "allergen"
