"""CareCart Fit scoring — the pure lifestyle curves and the medicines model."""

from __future__ import annotations

import datetime as dt

import pytest

from app.models import (
    DrugClassLookup,
    InteractionRule,
    Medication,
    RiskCompound,
    ScanHistory,
    User,
)
from app.services.fit import (
    alcohol_score,
    compute_fit,
    compute_lifestyle,
    compute_medicines,
    exercise_score,
    fit_tier,
    sleep_score,
    smoking_score,
    stress_score,
)


# ------------------------------------------------------------- lifestyle curves
@pytest.mark.parametrize(
    "h,expected",
    [(7, 100), (8, 100), (9, 100), (6.5, 85), (6, 70), (5.5, 55), (5, 40),
     (4, 20), (9.75, 70), (10.5, 40), (11, 30), (12, 20)],
)
def test_sleep_curve(h, expected):
    assert sleep_score(h) == pytest.approx(expected)


@pytest.mark.parametrize(
    "d,expected", [(0, 25), (1, 45), (3, 76), (5, 93), (7, 100), (9, 100), (-2, 25)]
)
def test_exercise_curve(d, expected):
    assert exercise_score(d) == expected


def test_categorical_curves():
    assert smoking_score("none") == 100
    assert smoking_score("daily") == 12
    assert alcohol_score("weekly") == 58
    assert stress_score(1) == 100
    assert stress_score(5) == 22
    assert stress_score(99) == 64  # unknown -> mid


def test_lifestyle_overall_is_weighted_mean_of_answered_dims():
    r = compute_lifestyle(
        {"sleep_hours": 8, "exercise_days": 4, "smoking": "none",
         "alcohol": "occasional", "stress": 3}
    )
    # 100*.24 + 86*.22 + 100*.22 + 82*.16 + 64*.16 all over 1.0
    assert r.overall == 88
    assert r.answered == 5
    assert {d.key for d in r.dims} == {
        "sleep", "exercise", "smoking", "alcohol", "stress"
    }


def test_partial_answers_renormalise_weights():
    r = compute_lifestyle({"sleep_hours": 6, "stress": 5})
    # (70*.24 + 22*.16) / (.24+.16) = (16.8 + 3.52) / .4 = 50.8 -> 51
    assert r.overall == 51
    assert r.answered == 2


def test_no_answers_is_none():
    assert compute_lifestyle(None).overall is None
    assert compute_lifestyle({}).overall is None


def test_fit_tier_thresholds():
    assert fit_tier(75) == "well matched"
    assert fit_tier(74) == "some tension"
    assert fit_tier(50) == "some tension"
    assert fit_tier(49) == "needs attention"


# ---------------------------------------------------------------- medicines
def _user(db) -> User:
    from app.core.security import hash_phone
    u = User(phone_hash=hash_phone("+919933000001"))
    db.add(u)
    db.flush()
    return u


def _seed_rules(db):
    db.add_all([
        RiskCompound(risk_compound="sodium", display_name="Sodium"),
        RiskCompound(risk_compound="potassium", display_name="Potassium"),
    ])
    db.flush()
    db.add(DrugClassLookup(
        active_ingredient="telmisartan", drug_class="ARB", source="keyword"))
    db.add(InteractionRule(
        drug_class="ARB", risk_compound="sodium", severity="HIGH"))
    db.add(InteractionRule(
        drug_class="ARB", risk_compound="potassium", severity="MODERATE"))
    db.flush()


def _scan(db, user_id, *, factor, days_ago, score=40):
    db.add(ScanHistory(
        user_id=user_id,
        product_name="x",
        score=score,
        tier="caution",
        key_reasons=[{"kind": "condition_ceiling", "severity": "high",
                      "title": "t", "factor": factor}],
        scanned_at=dt.datetime.now(dt.UTC) - dt.timedelta(days=days_ago),
    ))


def test_medicines_none_when_no_meds(db):
    u = _user(db)
    r = compute_medicines(db, u.id)
    assert r.overall is None and r.meds == []


def test_medicine_with_no_interactions_scores_100(db):
    u = _user(db)
    _seed_rules(db)
    db.add(Medication(user_id=u.id, name="Paracetamol"))  # not in the lookup
    db.add(Medication(user_id=u.id, name="Telmisartan 40"))
    # not enough scans yet
    db.flush()
    r = compute_medicines(db, u.id)
    by_name = {m.name: m for m in r.meds}
    assert by_name["Paracetamol"].identified is False
    assert by_name["Telmisartan 40"].identified is True
    assert by_name["Telmisartan 40"].score is None  # 0 scans < 4


def test_medicine_score_falls_with_the_hit_rate(db):
    u = _user(db)
    _seed_rules(db)
    db.add(Medication(user_id=u.id, name="Telmisartan 40"))
    # 10 scans in the last 21 days; 8 flag sodium, 0 flag potassium
    for i in range(8):
        _scan(db, u.id, factor="sodium", days_ago=i + 1)
    for i in range(2):
        _scan(db, u.id, factor="added_sugar", days_ago=i + 1)
    db.flush()

    r = compute_medicines(db, u.id)
    assert r.scans_in_window == 10
    med = r.meds[0]
    # sodium hit_rate 0.8, HIGH: 100 - 1.0*0.8*90 = 28 (this is the worst rule)
    # potassium hit_rate 0.0, MODERATE: 100
    # mean = (28*1.0 + 100*0.65) / 1.65 = 56.36
    # combined = 0.7*28 + 0.3*56.36 = 36.5 -> 37
    assert med.score == 37
    assert "Sodium" in med.note
    assert med.interactions == ["Potassium", "Sodium"]


def test_fit_combines_halves_and_reports_focus(db):
    u = _user(db)
    _seed_rules(db)
    db.add(Medication(user_id=u.id, name="Telmisartan 40"))
    for i in range(10):
        _scan(db, u.id, factor="sodium", days_ago=i + 1)
    db.flush()

    res = compute_fit(
        db, u.id,
        lifestyle_data={"sleep_hours": 8, "exercise_days": 5, "smoking": "none",
                        "alcohol": "none", "stress": 2},
    )
    assert res.lifestyle.overall is not None
    assert res.medicines.overall is not None
    assert res.score == round(0.5 * res.lifestyle.overall + 0.5 * res.medicines.overall)
    assert res.tier in {"well matched", "some tension", "needs attention"}
    # lifestyle is strong, sodium hammers the medicine -> focus is the medicine
    assert res.focus is not None and res.focus.area == "medicines"


def test_fit_is_lifestyle_only_when_no_meds(db):
    u = _user(db)
    res = compute_fit(db, u.id, lifestyle_data={"sleep_hours": 8, "stress": 1})
    assert res.medicines.overall is None
    assert res.score == res.lifestyle.overall
