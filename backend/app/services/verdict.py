"""Food-drug interaction & severity scoring (Phase 4.4).

Takes a product's resolved risk compounds (Phase 4.3) plus the authenticated
user's stored conditions, allergies and active medications (Phase 3) and
produces a **0-100 score** and a **tier** using the exact thresholds from the
Flutter theme (``chipFor()`` in Phase 2.1):

    score >= 70 -> safe,  score >= 45 -> caution,  else avoid

Model: start at 100 and subtract a deduction for each matched risk factor -
- a **drug-food interaction pattern** (``interaction_rules``, e.g. warfarin /
  vitamin K, lithium / sodium),
- a **condition-specific nutrient ceiling** exceeded (``condition_diet_rules``),
- a **condition-specific risk compound** present,
- a **general poor-fit** ingredient (high sugar / sodium / sat-fat / trans-fat /
  refined carb not otherwise tied to the user),
- **unverified** ingredients (Phase 4.3 couldn't confirm them).

Precedence when a product matches several rules at once:
  1. **Allergen match wins outright** - score 0, tier ``avoid``, ``hard_stop``,
     no matter the arithmetic. Allergens are a full stop, not a deduction.
  2. Otherwise **all other factors stack additively**. They are de-duped first:
     a compound cited by a drug interaction or a condition rule is not also
     counted as general poor-fit, and two nutrient keys for one concern
     (``sodium_mg`` + ``salt_g``) count once. Score is clamped to 0-100.
  3. **HIGH-severity floor**: if any HIGH-severity drug interaction / condition
     ceiling / condition compound fired, the tier is at least ``caution`` even
     if the number lands >= 70.
  4. Reasons are returned most-serious first:
     allergen > drug_interaction > condition_ceiling > condition_compound >
     poor_fit > unverified > clear, then by points.

Brand vs generic: a stored medication name is run through ``drug_name_aliases``
(brand -> generic) before the ``drug_class_lookup`` / stem-rule match, so
"Ecosprin" is checked as "aspirin". A name that still resolves to no class is
reported (``identified: False``) and skipped for interactions - never a silent
pass.

Nothing here is medical advice: ``interaction_rules`` is a clinician-review
DRAFT and the wording stays "keep consistent" / "caution" style.
"""

from __future__ import annotations

import re
from collections import defaultdict
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import (
    AllergenAlias,
    ConditionDietRule,
    DrugClassLookup,
    DrugClassStemRule,
    DrugNameAlias,
    InteractionRule,
    RiskCompound,
)
from app.services.ingredient_risk import RiskResolution

# ------------------------------------------------------------------ tiers (2.1)
SAFE_MIN = 70
CAUTION_MIN = 45


def tier_for(score: int) -> str:
    if score >= SAFE_MIN:
        return "safe"
    if score >= CAUTION_MIN:
        return "caution"
    return "avoid"


# ---------------------------------------------------------------- deduction weights
_INTERACTION_POINTS = {"HIGH": 35, "MODERATE": 20, "LOW": 8}
_CEILING_POINTS = {"HIGH": 28, "MODERATE": 16, "LOW": 8}
_CEILING_OVERSHOOT_BONUS = 10  # added when the value is >= 2x the ceiling
_CEILING_MAX = 40
_CONDITION_COMPOUND_POINTS = {"HIGH": 28, "MODERATE": 14, "LOW": 7}
_POOR_FIT_COMPOUNDS = {"added_sugar", "sodium", "saturated_fat", "trans_fat", "rapid_carb"}
_POOR_FIT_CAP = 18

# Step 7b tie-in: a poor lifestyle dimension amplifies the deduction for the
# nutrition concern it compounds. Applied ONLY to condition-ceiling and general
# poor-fit deductions — never to allergens or the drug-interaction deduction.
# risk_compound -> lifestyle dimension key (see app/services/fit.py).
_LIFESTYLE_AMPLIFIERS = {
    "added_sugar": "stress",
    "rapid_carb": "exercise",
    "saturated_fat": "exercise",
}
_LIFE_MULT_HARD = (35, 1.25)   # dim sub-score < 35 -> x1.25
_LIFE_MULT_SOFT = (50, 1.15)   # dim sub-score < 50 -> x1.15
_CEILING_MAX_WITH_LIFESTYLE = 50


def _life_mult(
    factor: str | None, lifestyle_scores: dict[str, int] | None
) -> tuple[float, str | None]:
    """(multiplier, one-line note) for a deduction on ``factor``. 1.0 / None
    unless the mapped lifestyle dimension was answered AND is poor."""
    dim = _LIFESTYLE_AMPLIFIERS.get(factor or "")
    if not dim or not lifestyle_scores or dim not in lifestyle_scores:
        return 1.0, None
    s = lifestyle_scores[dim]
    if s < _LIFE_MULT_HARD[0]:
        return _LIFE_MULT_HARD[1], f"{dim} {s}/100 ×{_LIFE_MULT_HARD[1]:g} on {factor}"
    if s < _LIFE_MULT_SOFT[0]:
        return _LIFE_MULT_SOFT[1], f"{dim} {s}/100 ×{_LIFE_MULT_SOFT[1]:g} on {factor}"
    return 1.0, None
_UNVERIFIED_PER = 4
_UNVERIFIED_CAP = 12

_NUTRIENT_LABEL = {
    "sodium_mg_100g": "sodium",
    "salt_g_100g": "salt",
    "sugars_g_100g": "sugar",
    "saturated_fat_g_100g": "saturated fat",
    "fat_g_100g": "fat",
    "carbohydrates_g_100g": "carbohydrate",
    "energy_kcal_100g": "energy",
}
# a fired nutrient ceiling "covers" this compound for the same condition, so the
# sibling condition risk_compound rule doesn't also deduct for it
_CEILING_COVERS = {
    "sodium_mg_100g": "sodium",
    "salt_g_100g": "sodium",
    "sugars_g_100g": "added_sugar",
    "saturated_fat_g_100g": "saturated_fat",
}


# ------------------------------------------------------------------ name cleaning
_DOSE_RE = re.compile(r"\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|iu|%|units?)\b")
_FORM_RE = re.compile(
    r"\b(tablet|tablets|tab|tabs|caps?|capsule|capsules|syrup|suspension|susp|oral|"
    r"injection|inj|sr|xr|er|cr|xl|od|bd|tds|qds|drops?|cream|ointment|gel|lotion|"
    r"solution|sachet|powder|forte|plus|retard)\b"
)
_CONDITION_ALIASES = {
    "high blood pressure": "hypertension",
    "raised blood pressure": "hypertension",
    "htn": "hypertension",
    "high bp": "hypertension",
    "raised bp": "hypertension",
    "bp": "hypertension",
    "diabetes": "type 2 diabetes",
    "diabetes mellitus": "type 2 diabetes",
    "type ii diabetes": "type 2 diabetes",
    "type 2 diabetes mellitus": "type 2 diabetes",
    "t2dm": "type 2 diabetes",
    "dm": "type 2 diabetes",
    "sugar": "type 2 diabetes",
    "ckd": "chronic kidney disease",
    "kidney disease": "chronic kidney disease",
    "chronic renal failure": "chronic kidney disease",
    "renal failure": "chronic kidney disease",
    "hyperlipidemia": "high cholesterol",
    "hyperlipidaemia": "high cholesterol",
    "dyslipidemia": "high cholesterol",
    "dyslipidaemia": "high cholesterol",
    "high ldl": "high cholesterol",
    "raised cholesterol": "high cholesterol",
    "celiac": "coeliac disease",
    "celiac disease": "coeliac disease",
    "coeliac": "coeliac disease",
    "chf": "heart failure",
    "congestive heart failure": "heart failure",
    "cardiac failure": "heart failure",
    "acid reflux": "gerd",
    "reflux": "gerd",
    "gord": "gerd",
    "acidity": "gerd",
}


def _norm_drug(name: str) -> str:
    s = (name or "").lower()
    s = _DOSE_RE.sub(" ", s)
    s = _FORM_RE.sub(" ", s)
    s = re.sub(r"[^a-z\s/+-]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def _norm_condition(name: str) -> str:
    s = re.sub(r"[^a-z0-9\s]", " ", (name or "").lower())
    s = re.sub(r"\s+", " ", s).strip()
    return _CONDITION_ALIASES.get(s, s)


# ---------------------------------------------------------------------- results
@dataclass
class VerdictReason:
    kind: str        # allergen | drug_interaction | condition_ceiling |
    #                  condition_compound | poor_fit | unverified | clear
    severity: str    # high | moderate | low | info
    points: int      # score deducted (0 for allergen hard-stop and info lines)
    title: str
    detail: str | None = None
    # the recurring risk_compound this reason is about (sodium, added_sugar, …);
    # None for unverified / clear. Phase 5.3 groups repeat scans by this.
    factor: str | None = None


@dataclass
class MedMatch:
    name: str
    drug_classes: list[str]
    identified: bool


@dataclass
class Verdict:
    score: int
    tier: str
    hard_stop: bool
    reasons: list[VerdictReason] = field(default_factory=list)
    medications: list[MedMatch] = field(default_factory=list)
    risk_compounds: dict[str, float] = field(default_factory=dict)
    unverified: list[str] = field(default_factory=list)
    # 7b: human-readable list of the lifestyle multipliers that were applied,
    # e.g. ["stress 22/100 ×1.25 on added_sugar"]. Empty when none.
    lifestyle_applied: list[str] = field(default_factory=list)


# ----------------------------------------------------------------- reference load
@dataclass
class _Rules:
    display: dict[str, str]
    lookup: dict[str, str]
    stems: list[tuple[int, str, str, str]]
    interactions: dict[str, list[InteractionRule]]
    conditions: dict[str, list[ConditionDietRule]]
    allergens: list[tuple[str, str]]  # (alias, risk_compound)
    name_aliases: dict[str, str]      # brand -> generic active ingredient


def _load_rules(db: Session) -> _Rules:
    display = {
        rc: name
        for rc, name in db.execute(
            select(RiskCompound.risk_compound, RiskCompound.display_name)
        ).all()
    }
    lookup = {
        ing: cls
        for ing, cls in db.execute(
            select(DrugClassLookup.active_ingredient, DrugClassLookup.drug_class)
        ).all()
    }
    stems = [
        (r.ordinal, r.pattern, r.position, r.drug_class)
        for r in db.scalars(select(DrugClassStemRule)).all()
    ]
    stems.sort(key=lambda t: t[0])

    interactions: dict[str, list[InteractionRule]] = defaultdict(list)
    for rule in db.scalars(select(InteractionRule)).all():
        interactions[rule.drug_class].append(rule)

    conditions: dict[str, list[ConditionDietRule]] = defaultdict(list)
    for rule in db.scalars(select(ConditionDietRule)).all():
        conditions[rule.condition].append(rule)

    allergens = [
        (a.alias, a.risk_compound)
        for a in db.scalars(select(AllergenAlias)).all()
    ]
    name_aliases = {
        alias: generic
        for alias, generic in db.execute(
            select(DrugNameAlias.alias, DrugNameAlias.generic)
        ).all()
    }
    return _Rules(
        display, lookup, stems, interactions, conditions, allergens, name_aliases
    )


def _drug_classes_for(name: str, rules: _Rules) -> list[str]:
    s = _norm_drug(name)
    if not s:
        return []
    out: list[str] = []
    seen: set[str] = set()

    def _add(cls: str) -> None:
        if cls and cls not in seen:
            out.append(cls)
            seen.add(cls)

    # brand -> generic first: the stored name is usually a brand, the tables key
    # off the generic. Map the whole string and each token.
    candidates = [s]
    if s in rules.name_aliases:
        candidates.append(rules.name_aliases[s])
    for t in re.split(r"[\s/+-]+", s):
        if t in rules.name_aliases:
            candidates.append(rules.name_aliases[t])

    for cand in candidates:
        if cand in rules.lookup:
            _add(rules.lookup[cand])
    tokens = [
        t
        for cand in candidates
        for t in re.split(r"[\s/+-]+", cand)
        if len(t) >= 4
    ]
    for t in tokens:
        if t in rules.lookup:
            _add(rules.lookup[t])
    if out:
        return out
    # stem-rule fallback on the longest token
    for t in sorted((t for t in tokens if len(t) >= 5), key=len, reverse=True):
        for _ordinal, pattern, position, cls in rules.stems:
            hit = (position == "suffix" and t.endswith(pattern)) or (
                position == "prefix" and t.startswith(pattern)
            )
            if hit and len(t) > len(pattern) + 1:
                _add(cls)
                return out
    return out


def _user_allergen_compounds(allergies: list[str], rules: _Rules) -> dict[str, str]:
    """risk_compound -> the user's allergy label that produced it."""
    hits: dict[str, str] = {}
    for raw in allergies:
        text = " " + re.sub(r"[^a-z0-9\s]", " ", (raw or "").lower()) + " "
        text = re.sub(r"\s+", " ", text)
        for alias, rc in rules.allergens:
            if re.search(r"\b" + re.escape(alias) + r"\b", text):
                hits.setdefault(rc, raw.strip())
    return hits


# --------------------------------------------------------------------- scoring
def score_verdict(
    db: Session,
    *,
    resolution: RiskResolution,
    conditions: list[str],
    allergies: list[str],
    medications: list[str],
    nutriments: dict | None = None,
    lifestyle_scores: dict[str, int] | None = None,
) -> Verdict:
    rules = _load_rules(db)
    nutriments = nutriments or {}
    lifestyle_applied: list[str] = []

    def disp(rc: str) -> str:
        return rules.display.get(rc, rc.replace("_", " "))

    reasons: list[VerdictReason] = []
    deduction = 0
    cited: set[str] = set()  # risk_compounds already explained by a med/condition

    # ---- 1. allergens: hard stop, not a deduction ----
    user_allergens = _user_allergen_compounds(allergies, rules)
    allergen_seen: set[tuple[str, str]] = set()
    for ing in resolution.ingredients:
        for rc in ing.risk_compounds:
            if rc in user_allergens and (rc, ing.clean_text) not in allergen_seen:
                allergen_seen.add((rc, ing.clean_text))
                reasons.append(
                    VerdictReason(
                        kind="allergen",
                        severity="high",
                        points=0,
                        title=f"Contains {disp(rc)} — you told us you're allergic to "
                        f"{user_allergens[rc]}",
                        detail=f"Ingredient flagged: “{ing.input_text}”. An allergen match "
                        "is a full stop, not a score deduction.",
                        factor=rc,
                    )
                )
    hard_stop = bool(allergen_seen)

    # ---- 2. drug-food interaction patterns ----
    med_matches: list[MedMatch] = []
    interaction_seen: set[tuple[str, str]] = set()
    for med in medications:
        classes = _drug_classes_for(med, rules)
        med_matches.append(MedMatch(name=med, drug_classes=classes, identified=bool(classes)))
        for cls in classes:
            for rule in rules.interactions.get(cls, []):
                if rule.risk_compound not in resolution.risk_compounds:
                    continue
                key = (cls, rule.risk_compound)
                if key in interaction_seen:
                    continue
                interaction_seen.add(key)
                pts = _INTERACTION_POINTS.get(rule.severity, 15)
                deduction += pts
                cited.add(rule.risk_compound)
                detail = (rule.mechanism or "").strip()
                if rule.dietary_guidance:
                    detail = f"{detail} {rule.dietary_guidance.strip()}".strip()
                reasons.append(
                    VerdictReason(
                        kind="drug_interaction",
                        severity=rule.severity.lower(),
                        points=pts,
                        title=f"{med.strip()} ({cls}) interacts with {disp(rule.risk_compound)}",
                        detail=detail or None,
                        factor=rule.risk_compound,
                    )
                )
    if any(not m.identified for m in med_matches):
        unknown = ", ".join(m.name.strip() for m in med_matches if not m.identified)
        reasons.append(
            VerdictReason(
                kind="unverified",
                severity="low",
                points=0,
                title="Couldn't identify the drug class for some of your medications",
                detail=f"Not checked for interactions: {unknown}. Confirm the name or add "
                "it from a label scan.",
            )
        )

    # ---- 3. condition-specific rules ----
    condition_seen: set[str] = set()
    for cond in conditions:
        ncond = _norm_condition(cond)
        crules = rules.conditions.get(ncond, [])
        # pass 1: numeric nutrient ceilings
        covered: set[str] = set()
        for rule in crules:
            if rule.kind != "nutrient_ceiling":
                continue
            rid = f"{ncond}:{rule.id}"
            if rid in condition_seen:
                continue
            try:
                val = float(nutriments.get(rule.nutrient_key))
            except (TypeError, ValueError):
                continue
            if rule.ceiling_per_100g is None or val <= rule.ceiling_per_100g:
                continue
            _cov = _CEILING_COVERS.get(rule.nutrient_key, "")
            # two nutriment keys for the same concern (sodium_mg + salt_g) must
            # not both deduct for one condition - first (more specific) wins
            if _cov and _cov in covered:
                continue
            condition_seen.add(rid)
            covered.add(_cov)
            if _cov:
                cited.add(_cov)  # general poor-fit shouldn't also deduct for it
            pts = _CEILING_POINTS.get(rule.severity, 16)
            if val >= 2 * rule.ceiling_per_100g:
                pts = min(pts + _CEILING_OVERSHOOT_BONUS, _CEILING_MAX)
            _mult, _note = _life_mult(_cov or None, lifestyle_scores)
            if _note:
                pts = min(round(pts * _mult), _CEILING_MAX_WITH_LIFESTYLE)
                lifestyle_applied.append(_note)
            deduction += pts
            label = _NUTRIENT_LABEL.get(rule.nutrient_key, rule.nutrient_key)
            reasons.append(
                VerdictReason(
                    kind="condition_ceiling",
                    severity=rule.severity.lower(),
                    points=pts,
                    title=f"High {label} for {cond.strip()}",
                    detail=f"{round(val, 1)} per 100 g vs a {rule.ceiling_per_100g:g} "
                    f"per-100 g limit for {ncond}. {rule.guidance or ''}".strip(),
                    factor=_cov or None,
                )
            )
        # pass 2: risk-compound rules (skip any a ceiling already covered)
        for rule in crules:
            if rule.kind != "risk_compound":
                continue
            rid = f"{ncond}:{rule.id}"
            if rid in condition_seen or rule.risk_compound in covered:
                continue
            if rule.risk_compound not in resolution.risk_compounds:
                continue
            condition_seen.add(rid)
            pts = _CONDITION_COMPOUND_POINTS.get(rule.severity, 12)
            deduction += pts
            cited.add(rule.risk_compound)
            reasons.append(
                VerdictReason(
                    kind="condition_compound",
                    severity=rule.severity.lower(),
                    points=pts,
                    title=f"{disp(rule.risk_compound)} is a poor fit for {cond.strip()}",
                    detail=rule.guidance,
                    factor=rule.risk_compound,
                )
            )

    # ---- 4. general poor-fit ingredients (not tied to a med / condition) ----
    poor_fit_total = 0
    for rc, conf in sorted(resolution.risk_compounds.items()):
        if rc in cited or rc in user_allergens or rc not in _POOR_FIT_COMPOUNDS:
            continue
        pts = 6 if (conf or 0) >= 0.6 else 3
        _mult, _note = _life_mult(rc, lifestyle_scores)
        if _note:
            pts = round(pts * _mult)
            lifestyle_applied.append(_note)
        pts = min(pts, _POOR_FIT_CAP - poor_fit_total)
        if pts <= 0:
            break
        poor_fit_total += pts
        deduction += pts
        reasons.append(
            VerdictReason(
                kind="poor_fit",
                severity="low",
                points=pts,
                title=f"High {disp(rc)}",
                factor=rc,
                detail="A general nutrition concern — not tied to your medications or conditions.",
            )
        )

    # ---- 5. unverified ingredients (Phase 4.3) ----
    if resolution.unverified:
        n = len(resolution.unverified)
        pts = min(n * _UNVERIFIED_PER, _UNVERIFIED_CAP)
        deduction += pts
        title = (
            resolution.caution_factors[0]
            if resolution.caution_factors
            else f"Couldn't confirm {n} ingredient(s) in this product"
        )
        reasons.append(
            VerdictReason(
                kind="unverified",
                severity="low",
                points=pts,
                title=title,
                detail="Not in our reference tables yet: "
                + ", ".join(resolution.unverified[:8])
                + ("…" if n > 8 else ""),
            )
        )

    # ---- score + tier (precedence) ----
    # 1. an allergen match is an absolute hard stop - score 0 / avoid, no matter
    #    what the arithmetic says.
    # 2. otherwise every factor stacks additively (already de-duped so one
    #    compound is never counted twice), clamped to 0-100, mapped to a tier on
    #    the exact Phase 2.1 thresholds.
    # 3. a floor: if any HIGH-severity clinical factor fired (a well-established
    #    drug-food interaction, or a condition ceiling / compound), the verdict
    #    can't read "Safe for you" even if the number lands >= 70 - it is at
    #    least "caution".
    score = max(0, min(100, 100 - deduction))
    if hard_stop:
        score = 0
        tier = "avoid"
    else:
        tier = tier_for(score)
        _high_clinical = {"drug_interaction", "condition_ceiling", "condition_compound"}
        if tier == "safe" and any(
            r.severity == "high" and r.kind in _high_clinical for r in reasons
        ):
            tier = "caution"

    if not reasons:
        reasons.append(
            VerdictReason(
                kind="clear",
                severity="info",
                points=0,
                title="No conflicts found with your medications, conditions, or allergies.",
            )
        )

    _order = {
        "allergen": 0, "drug_interaction": 1, "condition_ceiling": 2,
        "condition_compound": 3, "poor_fit": 4, "unverified": 5, "clear": 6,
    }
    reasons.sort(key=lambda r: (_order.get(r.kind, 9), -r.points))

    return Verdict(
        score=score,
        tier=tier,
        hard_stop=hard_stop,
        reasons=reasons,
        medications=med_matches,
        risk_compounds=resolution.risk_compounds,
        unverified=resolution.unverified,
        lifestyle_applied=lifestyle_applied,
    )
