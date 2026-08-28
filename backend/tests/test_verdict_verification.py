"""Phase 4.4 VERIFICATION - POST /scan/verdict end to end.

Covers, with printed output (`pytest -s`):
  1. no risk factors + no conditions            -> high `safe` score
  2. known allergen + that allergy               -> hard `avoid`, regardless of
     other (severe) factors
  3. a known interaction pattern                 -> lands in the 45-69 `caution` band
  4. multiple stacked severe factors             -> lands below 45 (`avoid`)
  5. tier matches score EXACTLY at the 70 and 45 boundaries

Runs against the real reference tables (loaded once) and the real HTTP route.
"""

from __future__ import annotations

import pytest
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, hash_phone
from app.models import Allergy, Condition, Medication, User
from app.services import verdict as V
from scripts.load_risk_tables import load_all


@pytest.fixture(scope="module", autouse=True)
def _ref_data(engine):
    with Session(engine) as s:
        load_all(s, settings.risk_data_path)
    yield


@pytest.fixture
def user(db) -> User:
    u = User(phone_hash=hash_phone("+919555100001"))
    db.add(u)
    db.flush()
    return u


@pytest.fixture
def auth(user) -> dict:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _vault(db, user, *, conditions=(), allergies=(), meds=()):
    for c in conditions:
        db.add(Condition(user_id=user.id, condition_name=c))
    for a in allergies:
        db.add(Allergy(user_id=user.id, allergen_name=a))
    for m in meds:
        db.add(Medication(user_id=user.id, name=m))
    db.flush()


def _post(client, auth, **body):
    r = client.post("/api/v1/scan/verdict", headers=auth, json=body)
    assert r.status_code == 200, r.text
    return r.json()


def _show(tag: str, body: dict) -> None:
    print(f"\n===== {tag} =====")
    print(f"score={body['score']}  tier={body['tier']}  hard_stop={body['hard_stop']}")
    if body["medications"]:
        print("medications:")
        for m in body["medications"]:
            print(f"  - {m['name']!r}: {m['drug_classes'] or 'NOT IDENTIFIED'}")
    print("reasons:")
    for r in body["reasons"]:
        print(f"  [{r['kind']}/{r['severity']} -{r['points']}] {r['title']}")


# --------------------------------------------------------------------------- #
def test_1_no_risk_factors_no_conditions_scores_high_safe(client, db, user, auth):
    body = _post(
        client, auth,
        ingredients=["Rolled oats", "Water", "Cinnamon"],
        nutriments={"sugars_g_100g": 1.0, "sodium_mg_100g": 4.0},
    )
    _show("CASE 1 - no risk factors, empty vault", body)
    assert body["score"] >= 90
    assert body["score"] <= 100
    assert body["tier"] == "safe"
    assert body["hard_stop"] is False
    assert [r["kind"] for r in body["reasons"]] == ["clear"]


def test_2_allergen_forces_hard_avoid_regardless_of_other_factors(client, db, user, auth):
    # user also on warfarin + lithium and the product also carries two HIGH
    # interaction hits - the allergen must still win outright.
    _vault(db, user, allergies=["Peanuts"], meds=["Warfarin", "Lithium carbonate"])
    body = _post(
        client, auth,
        ingredients=["Groundnut", "Broccoli", "Iodised salt"],
        nutriments={"sodium_mg_100g": 900},
        product_name="Peanut chikki",
    )
    _show("CASE 2 - allergen present (+ 2 severe interactions in the mix)", body)
    assert body["hard_stop"] is True
    assert body["tier"] == "avoid"
    assert body["score"] == 0  # a stop, not a computed number
    top = body["reasons"][0]
    assert top["kind"] == "allergen" and top["points"] == 0
    assert "Peanuts" in top["title"]
    # the other factors are still surfaced, they just don't change the outcome
    assert any(r["kind"] == "drug_interaction" for r in body["reasons"])


def test_3_moderate_interaction_lands_in_caution_band(client, db, user, auth):
    # one ACE-inhibitor drug, two MODERATE interaction rules fire
    # (ACE x sodium, ACE x licorice) = -20 -20 -> 60.
    _vault(db, user, meds=["Ramipril 5mg"])
    body = _post(
        client, auth,
        ingredients=["Iodised salt", "Mulethi extract"],
        product_name="Digestive candy",
    )
    _show("CASE 3 - moderate interaction risk", body)
    assert 45 <= body["score"] <= 69
    assert body["tier"] == "caution"
    assert body["hard_stop"] is False
    inter = [r for r in body["reasons"] if r["kind"] == "drug_interaction"]
    assert len(inter) == 2 and all(r["severity"] == "moderate" for r in inter)
    assert body["score"] == 60


def test_4_stacked_severe_factors_land_below_45(client, db, user, auth):
    # warfarin x vitamin K (HIGH -35) + lithium x sodium (HIGH -35) = -70 -> 30
    _vault(db, user, meds=["Warfarin", "Lithium carbonate 300mg"])
    body = _post(
        client, auth,
        ingredients=["Broccoli", "Iodised salt", "Wheat flour"],
        product_name="Palak sev",
    )
    _show("CASE 4 - multiple stacked severe factors", body)
    assert body["score"] < 45
    assert body["tier"] == "avoid"
    assert body["hard_stop"] is False  # avoid by SCORE, not a hard stop
    high = [
        r for r in body["reasons"]
        if r["kind"] == "drug_interaction" and r["severity"] == "high"
    ]
    assert len(high) == 2
    assert body["score"] == 30


# --------------------------------------------------------------------------- #
# tier must match the score EXACTLY at both boundaries
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize(
    "score,tier",
    [(71, "safe"), (70, "safe"), (69, "caution"),
     (46, "caution"), (45, "caution"), (44, "avoid")],
)
def test_5a_tier_function_at_the_boundaries(score, tier):
    assert V.tier_for(score) == tier


def test_5b_returned_tier_is_exactly_safe_at_score_70(client, db, user, auth):
    # ACE x sodium MODERATE (-20) + added_sugar poor-fit (-6) + 1 unverified (-4) = -30
    _vault(db, user, meds=["Ramipril 5mg"])
    body = _post(
        client, auth,
        ingredients=["Iodised salt", "Sugar", "Z%rblaxine powder"],
        product_name="Boundary snack A",
    )
    _show("CASE 5b - constructed to land on exactly 70", body)
    assert body["score"] == 70
    assert body["tier"] == "safe"  # 70 is safe, not caution


def test_5c_returned_tier_is_exactly_caution_at_score_45(client, db, user, auth):
    # warfarin x vitamin K (HIGH -35) + ACE x sodium (MODERATE -20) = -55 -> 45
    _vault(db, user, meds=["Warfarin", "Ramipril"])
    body = _post(
        client, auth,
        ingredients=["Broccoli", "Iodised salt"],
        product_name="Boundary snack B",
    )
    _show("CASE 5c - constructed to land on exactly 45", body)
    assert body["score"] == 45
    assert body["tier"] == "caution"  # 45 is caution, not avoid


def test_5d_every_returned_verdict_is_self_consistent(client, db, user, auth):
    """For any non-hard-stop verdict, tier == tier_for(score)."""
    _vault(db, user, conditions=["Type 2 diabetes"], meds=["Metformin 500mg"])
    for ings, nut in [
        (["Rolled oats"], {}),
        (["Sugar", "Refined wheat flour"], {"sugars_g_100g": 30}),
        (["Iodised salt", "Palm oil", "Sugar"], {"sodium_mg_100g": 900, "sugars_g_100g": 12}),
        (["Novelpolymer x7", "Water"], {}),
    ]:
        body = _post(client, auth, ingredients=ings, nutriments=nut)
        if not body["hard_stop"]:
            assert body["tier"] == V.tier_for(body["score"]), (ings, body["score"], body["tier"])
    print("\nCASE 5d - tier == tier_for(score) held for every sampled verdict")
