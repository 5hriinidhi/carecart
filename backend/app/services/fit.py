"""CareCart Fit — the medical + lifestyle correlation score (Step 7).

Two independently-computed halves, one overall number:

* **Lifestyle** — sleep, exercise, smoking, alcohol, stress, each mapped to a
  0-100 sub-score by a fixed piecewise curve, then a weighted mean.
* **Medicines** — for every stored medication with a known food interaction
  (resolved via the same drug-class tables the verdict engine uses), how often
  the user's recent scans flag the compound that drug reacts with. A high hit
  rate on a HIGH-severity interaction pulls that medicine's sub-score down.

Everything here is deterministic arithmetic over stored data — no LLM, no
network. Every constant is defined in this module and unit-tested in
``tests/test_fit.py``.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Medication, ScanHistory
from app.services.verdict import _drug_classes_for, _load_rules

# --------------------------------------------------------------------- lifestyle

# weights sum to 1.0 (see the spec table); a dimension the user didn't answer is
# dropped and the remaining weights renormalised.
LIFESTYLE_WEIGHTS = {
    "sleep": 0.24,
    "exercise": 0.22,
    "smoking": 0.22,
    "alcohol": 0.16,
    "stress": 0.16,
}

_EXERCISE_CURVE = {0: 25, 1: 45, 2: 62, 3: 76, 4: 86, 5: 93, 6: 98, 7: 100}
_SMOKING_CURVE = {"none": 100, "occasional": 45, "daily": 12}
_ALCOHOL_CURVE = {"none": 100, "occasional": 82, "weekly": 58, "daily": 25}
_STRESS_CURVE = {1: 100, 2: 84, 3: 64, 4: 42, 5: 22}


def _lerp(x: float, x0: float, x1: float, y0: float, y1: float) -> float:
    if x1 == x0:
        return y0
    t = (x - x0) / (x1 - x0)
    return y0 + t * (y1 - y0)


def sleep_score(hours: float) -> float:
    """100 in the 7-9 h band; linear down to 40 at 5 h / 10.5 h; 20 past that."""
    h = float(hours)
    if 7.0 <= h <= 9.0:
        return 100.0
    if 6.0 <= h < 7.0:
        return _lerp(h, 6.0, 7.0, 70.0, 100.0)
    if 5.0 <= h < 6.0:
        return _lerp(h, 5.0, 6.0, 40.0, 70.0)
    if 9.0 < h <= 10.5:
        return _lerp(h, 9.0, 10.5, 100.0, 40.0)
    if 10.5 < h <= 11.5:
        return _lerp(h, 10.5, 11.5, 40.0, 20.0)
    return 20.0  # < 5 h or > 11.5 h


def exercise_score(days: int) -> float:
    d = max(0, min(7, int(days)))
    return float(_EXERCISE_CURVE[d])


def smoking_score(value: str) -> float:
    return float(_SMOKING_CURVE.get(value, 100))


def alcohol_score(value: str) -> float:
    return float(_ALCOHOL_CURVE.get(value, 100))


def stress_score(level: int) -> float:
    return float(_STRESS_CURVE.get(int(level), 64))


@dataclass
class LifestyleDim:
    key: str          # sleep | exercise | smoking | alcohol | stress
    label: str
    score: int        # 0-100
    weight: float
    detail: str       # human one-liner ("6.2 h — below your 7 h target")


@dataclass
class LifestyleResult:
    overall: int | None            # None if nothing answered
    dims: list[LifestyleDim] = field(default_factory=list)
    answered: int = 0
    total: int = 5


def _sleep_detail(h: float) -> str:
    if 7.0 <= h <= 9.0:
        return f"{h:g} h — in the 7-9 h target band"
    if h < 7.0:
        return f"{h:g} h — below the 7 h target"
    return f"{h:g} h — above the 9 h target"


def compute_lifestyle(data: dict | None) -> LifestyleResult:
    d = data or {}
    dims: list[LifestyleDim] = []

    if d.get("sleep_hours") is not None:
        h = float(d["sleep_hours"])
        dims.append(LifestyleDim("sleep", "Sleep", round(sleep_score(h)),
                                 LIFESTYLE_WEIGHTS["sleep"], _sleep_detail(h)))
    if d.get("exercise_days") is not None:
        n = int(d["exercise_days"])
        dims.append(LifestyleDim(
            "exercise", "Exercise", round(exercise_score(n)),
            LIFESTYLE_WEIGHTS["exercise"],
            f"{n} day{'' if n == 1 else 's'}/week of activity"))
    if d.get("smoking") is not None:
        v = str(d["smoking"])
        dims.append(LifestyleDim(
            "smoking", "Smoking", round(smoking_score(v)),
            LIFESTYLE_WEIGHTS["smoking"],
            "Non-smoker" if v == "none" else f"Smokes {v}"))
    if d.get("alcohol") is not None:
        v = str(d["alcohol"])
        dims.append(LifestyleDim(
            "alcohol", "Alcohol", round(alcohol_score(v)),
            LIFESTYLE_WEIGHTS["alcohol"],
            "No alcohol" if v == "none" else f"Alcohol {v}"))
    if d.get("stress") is not None:
        lvl = int(d["stress"])
        dims.append(LifestyleDim(
            "stress", "Stress", round(stress_score(lvl)),
            LIFESTYLE_WEIGHTS["stress"], f"Self-rated {lvl}/5"))

    if not dims:
        return LifestyleResult(overall=None, dims=[], answered=0)

    wsum = sum(x.weight for x in dims)
    overall = round(sum(x.score * x.weight for x in dims) / wsum)
    return LifestyleResult(overall=overall, dims=dims, answered=len(dims))


# --------------------------------------------------------------------- medicines

_SEVERITY_FACTOR = {"HIGH": 1.0, "MODERATE": 0.65, "LOW": 0.35}
_HIT_RATE_PENALTY = 90.0     # full penalty at hit_rate 1.0 x severity 1.0
_MED_SCORE_FLOOR = 10
_MIN_SCANS_FOR_MED = 4       # need at least this many scans in the window
MED_WINDOW_DAYS = 21


@dataclass
class MedItem:
    name: str
    identified: bool           # did we resolve it to a drug class?
    score: int | None          # None = not enough recent scans to assess
    note: str
    interactions: list[str] = field(default_factory=list)  # display names


@dataclass
class MedicinesResult:
    overall: int | None        # None if no meds, or none assessable
    meds: list[MedItem] = field(default_factory=list)
    scans_in_window: int = 0


def _factor_hits(rows: list[ScanHistory]) -> dict[str, int]:
    """risk_compound -> how many of these scans flagged it."""
    hits: dict[str, int] = {}
    for r in rows:
        seen: set[str] = set()
        for reason in (r.key_reasons or []):
            f = reason.get("factor")
            if f and f not in seen:
                seen.add(f)
                hits[f] = hits.get(f, 0) + 1
    return hits


_WORST_WEIGHT = 0.7  # a medicine's score is dominated by its worst interaction,
_MEAN_WEIGHT = 0.3   # nudged down further if it has several bad ones


def _med_score(rules_for_class, hits: dict[str, int], total: int,
               display: dict[str, str]) -> tuple[int, str, list[str]]:
    """Per-interaction scores collapsed to one, driven by the WORST conflict so a
    clean low-severity rule can't mask a bad high-severity one. Returns
    (score, worst-note, [interaction display names])."""
    per_rule: list[tuple[float, float]] = []  # (score, severity_weight)
    worst: tuple[float, str] | None = None
    names: list[str] = []
    for rule in rules_for_class:
        sev = _SEVERITY_FACTOR.get(rule.severity, 0.35)
        rc = rule.risk_compound
        name = display.get(rc, rc.replace("_", " "))
        names.append(name)
        hit_rate = hits.get(rc, 0) / total if total else 0.0
        raw = 100.0 - sev * hit_rate * _HIT_RATE_PENALTY
        score = max(float(_MED_SCORE_FLOOR), min(100.0, raw))
        per_rule.append((score, sev))
        pct = round(hit_rate * 100)
        note = (
            f"{name} flagged in {pct}% of recent scans"
            if hit_rate > 0
            else f"{name} — clear in recent scans"
        )
        if worst is None or score < worst[0]:
            worst = (score, note)
    wsum = sum(w for _, w in per_rule) or 1.0
    mean = sum(s * w for s, w in per_rule) / wsum
    worst_score = worst[0] if worst else 100.0
    combined = round(_WORST_WEIGHT * worst_score + _MEAN_WEIGHT * mean)
    return combined, (worst[1] if worst else "no recent conflicts"), names


def compute_medicines(
    db: Session,
    user_id,
    *,
    now: dt.datetime | None = None,
    window_days: int = MED_WINDOW_DAYS,
    window_offset_days: int = 0,
) -> MedicinesResult:
    now = now or dt.datetime.now(dt.UTC)
    end = now - dt.timedelta(days=window_offset_days)
    start = end - dt.timedelta(days=window_days)

    med_names = [
        m.name
        for m in db.scalars(
            select(Medication).where(Medication.user_id == user_id)
        ).all()
    ]
    if not med_names:
        return MedicinesResult(overall=None, meds=[], scans_in_window=0)

    rows = list(
        db.scalars(
            select(ScanHistory).where(
                ScanHistory.user_id == user_id,
                ScanHistory.scanned_at > start,
                ScanHistory.scanned_at <= end,
            )
        ).all()
    )
    total = len(rows)
    hits = _factor_hits(rows)

    rules = _load_rules(db)
    items: list[MedItem] = []
    scored: list[int] = []
    for name in med_names:
        classes = _drug_classes_for(name, rules)
        if not classes:
            items.append(MedItem(name, identified=False, score=None,
                                 note="couldn't match this to a drug class"))
            continue
        rules_for = [
            rule for c in classes for rule in rules.interactions.get(c, [])
        ]
        if not rules_for:
            items.append(MedItem(
                name, identified=True, score=100,
                note="no food interactions on file", interactions=[]))
            scored.append(100)
            continue
        if total < _MIN_SCANS_FOR_MED:
            items.append(MedItem(
                name, identified=True, score=None,
                note=f"scan a few more labels ({total}/{_MIN_SCANS_FOR_MED})",
                interactions=sorted({
                    rules.display.get(r.risk_compound,
                                      r.risk_compound.replace("_", " "))
                    for r in rules_for
                })))
            continue
        score, note, names = _med_score(rules_for, hits, total, rules.display)
        items.append(MedItem(name, identified=True, score=score, note=note,
                             interactions=sorted(set(names))))
        scored.append(score)

    overall = round(sum(scored) / len(scored)) if scored else None
    return MedicinesResult(overall=overall, meds=items, scans_in_window=total)


# ------------------------------------------------------------------------- fit

@dataclass
class FitFocus:
    area: str        # "lifestyle" | "medicines"
    key: str
    label: str
    score: int
    message: str


@dataclass
class FitResult:
    score: int | None
    tier: str | None
    delta: int
    lifestyle: LifestyleResult
    medicines: MedicinesResult
    focus: FitFocus | None


def fit_tier(score: int) -> str:
    if score >= 75:
        return "well matched"
    if score >= 50:
        return "some tension"
    return "needs attention"


_FOCUS_MESSAGES = {
    "sleep": "Getting closer to 7-9 h a night lifts this the most.",
    "exercise": "Two or three more active days a week is the biggest single move.",
    "smoking": "Cutting down here outweighs any diet change you could make.",
    "alcohol": "Fewer drinking days is the highest-leverage change here.",
    "stress": "Bringing stress down a level meaningfully changes the picture.",
}


def _combine(life: int | None, meds: int | None) -> int | None:
    if life is not None and meds is not None:
        return round(0.5 * life + 0.5 * meds)
    return life if life is not None else meds


def compute_fit(
    db: Session, user_id, *, lifestyle_data: dict | None,
    now: dt.datetime | None = None,
) -> FitResult:
    now = now or dt.datetime.now(dt.UTC)
    life = compute_lifestyle(lifestyle_data)
    meds = compute_medicines(db, user_id, now=now)

    score = _combine(life.overall, meds.overall)
    tier = fit_tier(score) if score is not None else None

    # delta: recompute the medicines half on the *previous* window; lifestyle is
    # a point-in-time input we don't version, so its delta is 0.
    prev_meds = compute_medicines(
        db, user_id, now=now, window_offset_days=MED_WINDOW_DAYS
    )
    prev_score = _combine(life.overall, prev_meds.overall)
    delta = (score - prev_score) if (score is not None and prev_score is not None) else 0

    # focus: the dimension with the largest weighted gap from 100
    focus: FitFocus | None = None
    best_gap = -1.0
    for d in life.dims:
        gap = (100 - d.score) * d.weight
        if gap > best_gap:
            best_gap = gap
            focus = FitFocus("lifestyle", d.key, d.label, d.score,
                             _FOCUS_MESSAGES.get(d.key, ""))
    assessable_meds = [m for m in meds.meds if m.score is not None]
    if assessable_meds:
        w = 0.5 / len(assessable_meds)
        for m in assessable_meds:
            gap = (100 - m.score) * w
            if gap > best_gap:
                best_gap = gap
                focus = FitFocus(
                    "medicines", m.name, m.name, m.score,
                    f"Your recent scans are working against {m.name}. {m.note}.")

    return FitResult(
        score=score, tier=tier, delta=delta,
        lifestyle=life, medicines=meds, focus=focus,
    )
