"""Load the pre-built STATIC risk-reference CSVs into Postgres (Phases 4.3 + 4.4).

Deploy step - run once after ``alembic upgrade head`` and again whenever the
CSVs change (e.g. after the offline batch job merges new aliases):

    python -m scripts.load_risk_tables            # from backend/, venv active
    python -m scripts.load_risk_tables --data-dir /path/to/data_prep

Source (``settings.risk_data_path`` by default =
``gradient-ascend-mobile-app/project/dataset/data_prep``):

| CSV                          | table                     |
|------------------------------|---------------------------|
| risk_compounds.csv           | risk_compounds            |
| ingredient_aliases.csv       | ingredient_risk_aliases   (source='keyword') |
| llm_ingredient_tags.csv      | ingredient_risk_aliases   (source='llm', match_type='exact') |
| risk_nutrient_thresholds.csv | risk_nutrient_thresholds  |
| food_risk_tags.csv           | food_risk_tags            |
| interaction_rules.csv        | interaction_rules         |
| drug_class_lookup.csv        | drug_class_lookup         (source='keyword') |
| llm_drug_classes.csv         | drug_class_lookup         (source='llm') |
| drug_class_stem_rules.csv    | drug_class_stem_rules     |
| condition_diet_rules.csv     | condition_diet_rules      |
| allergen_aliases.csv         | allergen_aliases          |

Reference rows are fully replaced on each run (``TRUNCATE ... CASCADE``). The
``unresolved_ingredients`` queue is a runtime table and is never touched here.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
import uuid

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models import (
    AllergenAlias,
    ConditionDietRule,
    DrugClassLookup,
    DrugClassStemRule,
    FoodRiskTag,
    IngredientRiskAlias,
    InteractionRule,
    RiskCompound,
    RiskNutrientThreshold,
)

_RC_SPLIT = re.compile(r"[;,|]")


class LoadError(RuntimeError):
    pass


def _rows(path: str) -> list[dict]:
    if not os.path.exists(path):
        raise LoadError(f"missing CSV: {path}")
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def _alias_confidence(note: str) -> float:
    note = (note or "").lower()
    if "low confidence" in note or "flag for review" in note or "review" in note:
        return 0.7
    return 0.9


def _f(value) -> float | None:
    try:
        return float(value) if str(value).strip() != "" else None
    except (TypeError, ValueError):
        return None


def load_all(db: Session, data_dir: str) -> dict[str, int]:
    """Replace every reference table from the CSVs in ``data_dir``. Returns row
    counts. Raises :class:`LoadError` on an unknown ``risk_compound`` reference."""
    rc_rows = _rows(os.path.join(data_dir, "risk_compounds.csv"))
    valid_rc = {r["risk_compound"].strip() for r in rc_rows}

    alias_rows = _rows(os.path.join(data_dir, "ingredient_aliases.csv"))
    llm_rows = _rows(os.path.join(data_dir, "llm_ingredient_tags.csv"))
    thr_rows = _rows(os.path.join(data_dir, "risk_nutrient_thresholds.csv"))
    food_rows = _rows(os.path.join(data_dir, "food_risk_tags.csv"))
    irule_rows = _rows(os.path.join(data_dir, "interaction_rules.csv"))
    dclass_rows = _rows(os.path.join(data_dir, "drug_class_lookup.csv"))
    dllm_rows = _rows(os.path.join(data_dir, "llm_drug_classes.csv"))
    stem_rows = _rows(os.path.join(data_dir, "drug_class_stem_rules.csv"))
    cond_rows = _rows(os.path.join(data_dir, "condition_diet_rules.csv"))
    allergen_rows = _rows(os.path.join(data_dir, "allergen_aliases.csv"))

    problems: list[str] = []

    # ---- ingredient risk aliases (4.3) ----
    aliases: list[dict] = []
    for r in alias_rows:
        rc = r["risk_compound"].strip()
        if rc not in valid_rc:
            problems.append(f"ingredient_aliases.csv: '{r['alias']}' -> unknown '{rc}'")
            continue
        aliases.append(
            dict(
                id=uuid.uuid4(),
                alias=r["alias"].strip().lower(),
                risk_compound=rc,
                match_type=r["match_type"].strip() or "substring",
                confidence=_alias_confidence(r.get("notes", "")),
                source="keyword",
                notes=(r.get("notes") or "").strip() or None,
                rationale=None,
            )
        )

    for r in llm_rows:
        token = r["ingredient_clean"].strip().lower()
        if not token:
            continue
        rationale = (r.get("rationale") or "").strip() or None
        conf = _f(r.get("confidence"))
        rcs = [x.strip() for x in _RC_SPLIT.split(r.get("risk_compounds", "")) if x.strip()]
        rcs = [x for x in rcs if x not in ("none", "benign", "")]
        if not rcs:
            aliases.append(
                dict(id=uuid.uuid4(), alias=token, risk_compound=None,
                     match_type="exact", confidence=None, source="llm",
                     notes=None, rationale=rationale)
            )
            continue
        for rc in rcs:
            if rc not in valid_rc:
                problems.append(f"llm_ingredient_tags.csv: '{token}' -> unknown '{rc}'")
                continue
            aliases.append(
                dict(id=uuid.uuid4(), alias=token, risk_compound=rc,
                     match_type="exact", confidence=conf, source="llm",
                     notes=None, rationale=rationale)
            )

    # ---- nutrient thresholds (4.3) ----
    thresholds: list[dict] = []
    for r in thr_rows:
        rc = r["risk_compound"].strip()
        if rc not in valid_rc:
            problems.append(f"risk_nutrient_thresholds.csv: unknown '{rc}'")
            continue
        thresholds.append(
            dict(
                id=uuid.uuid4(),
                risk_compound=rc,
                nutrient_key=r["nutrient_key"].strip(),
                basis=(r.get("basis") or "per_100g").strip(),
                min_value=float(r["min_value"]),
                confidence=float(r["confidence"]),
                method=(r.get("method") or "threshold").strip(),
                source=(r.get("source") or "").strip() or None,
                rationale=(r.get("rationale") or "").strip() or None,
            )
        )

    # ---- food risk tags (4.3) ----
    foods: list[dict] = []
    for r in food_rows:
        rc = r["risk_compound"].strip()
        if rc not in valid_rc:
            problems.append(f"food_risk_tags.csv: {r.get('food_id')} -> unknown '{rc}'")
            continue
        foods.append(
            dict(id=uuid.uuid4(), food_id=r["food_id"].strip(), risk_compound=rc,
                 confidence=_f(r.get("confidence")),
                 method=(r.get("method") or "").strip() or None)
        )

    # ---- interaction rules (4.4) ----
    irules: list[dict] = []
    for r in irule_rows:
        rc = r["risk_compound"].strip()
        if rc not in valid_rc:
            problems.append(f"interaction_rules.csv: {r.get('drug_class')} -> unknown '{rc}'")
            continue
        irules.append(
            dict(
                id=uuid.uuid4(),
                drug_class=r["drug_class"].strip(),
                risk_compound=rc,
                severity=r["severity"].strip().upper(),
                mechanism=(r.get("mechanism") or "").strip() or None,
                dietary_guidance=(r.get("dietary_guidance") or "").strip() or None,
                evidence_strength=(r.get("evidence_strength") or "").strip() or None,
                example_drugs=(r.get("example_drugs") or "").strip() or None,
            )
        )

    # ---- drug class lookup + LLM fallback (4.4) ----
    dclasses: list[dict] = []
    for r in dclass_rows:
        ing = (r.get("active_ingredient") or "").strip().lower()
        cls = (r.get("drug_class") or "").strip()
        if not ing or not cls:
            continue
        dclasses.append(dict(id=uuid.uuid4(), active_ingredient=ing, drug_class=cls,
                             source="keyword", confidence=None))
    for r in dllm_rows:
        ing = (r.get("active_ingredient") or "").strip().lower()
        cls = (r.get("drug_class") or "").strip()
        if not ing or not cls:
            continue
        dclasses.append(dict(id=uuid.uuid4(), active_ingredient=ing, drug_class=cls,
                             source="llm", confidence=_f(r.get("confidence"))))

    # ---- drug class stem rules (4.4) ----
    stems: list[dict] = []
    for r in stem_rows:
        try:
            ordinal = int(r.get("order") or r.get("ordinal") or 0)
        except ValueError:
            ordinal = 0
        stems.append(
            dict(
                id=uuid.uuid4(),
                ordinal=ordinal,
                pattern=(r.get("pattern") or "").strip().lower(),
                position=(r.get("position") or "").strip().lower(),
                drug_class=(r.get("drug_class") or "").strip(),
            )
        )

    # ---- condition diet rules (4.4) ----
    conds: list[dict] = []
    for r in cond_rows:
        kind = (r.get("kind") or "").strip()
        rc = (r.get("risk_compound") or "").strip() or None
        if kind == "risk_compound" and rc not in valid_rc:
            problems.append(
                f"condition_diet_rules.csv: {r.get('condition')} -> unknown '{rc}'"
            )
            continue
        conds.append(
            dict(
                id=uuid.uuid4(),
                condition=(r.get("condition") or "").strip().lower(),
                kind=kind,
                nutrient_key=(r.get("nutrient_key") or "").strip() or None,
                ceiling_per_100g=_f(r.get("ceiling_per_100g")),
                risk_compound=rc,
                severity=(r.get("severity") or "MODERATE").strip().upper(),
                guidance=(r.get("guidance") or "").strip() or None,
            )
        )

    # ---- allergen aliases (4.4) ----
    allergens: list[dict] = []
    for r in allergen_rows:
        rc = (r.get("risk_compound") or "").strip()
        if rc not in valid_rc:
            problems.append(f"allergen_aliases.csv: '{r.get('alias')}' -> unknown '{rc}'")
            continue
        allergens.append(
            dict(id=uuid.uuid4(), alias=(r.get("alias") or "").strip().lower(),
                 risk_compound=rc, notes=(r.get("notes") or "").strip() or None)
        )

    if problems:
        raise LoadError(
            f"{len(problems)} reference problem(s):\n  " + "\n  ".join(problems[:25])
        )

    # replace everything (CASCADE from risk_compounds clears the FK-linked tables;
    # the two drug-class tables have no FK so are listed explicitly)
    db.execute(
        text(
            "TRUNCATE TABLE risk_compounds, drug_class_lookup, drug_class_stem_rules "
            "CASCADE"
        )
    )
    db.bulk_insert_mappings(
        RiskCompound,
        [
            dict(
                risk_compound=r["risk_compound"].strip(),
                display_name=r.get("display_name", "").strip(),
                category=(r.get("category") or "").strip() or None,
                description=(r.get("description") or "").strip() or None,
                typical_food_sources=(r.get("typical_food_sources") or "").strip() or None,
                why_it_matters_for_drugs=(r.get("why_it_matters_for_drugs") or "").strip()
                or None,
            )
            for r in rc_rows
        ],
    )
    db.bulk_insert_mappings(IngredientRiskAlias, aliases)
    db.bulk_insert_mappings(RiskNutrientThreshold, thresholds)
    db.bulk_insert_mappings(FoodRiskTag, foods)
    db.bulk_insert_mappings(InteractionRule, irules)
    db.bulk_insert_mappings(DrugClassLookup, dclasses)
    db.bulk_insert_mappings(DrugClassStemRule, stems)
    db.bulk_insert_mappings(ConditionDietRule, conds)
    db.bulk_insert_mappings(AllergenAlias, allergens)
    db.commit()

    return {
        "risk_compounds": len(rc_rows),
        "ingredient_risk_aliases": len(aliases),
        "  - keyword": sum(1 for a in aliases if a["source"] == "keyword"),
        "  - llm": sum(1 for a in aliases if a["source"] == "llm"),
        "risk_nutrient_thresholds": len(thresholds),
        "food_risk_tags": len(foods),
        "interaction_rules": len(irules),
        "drug_class_lookup": len(dclasses),
        "drug_class_stem_rules": len(stems),
        "condition_diet_rules": len(conds),
        "allergen_aliases": len(allergens),
    }


def main(argv: list[str] | None = None) -> int:
    from app.core.config import settings

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data-dir", default=settings.risk_data_path)
    args = ap.parse_args(argv)

    data_dir = os.path.abspath(args.data_dir)
    print(f"loading risk-reference CSVs from {data_dir}")
    db = SessionLocal()
    try:
        counts = load_all(db, data_dir)
    except LoadError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        db.close()
    for name, n in counts.items():
        print(f"  {name:<28} {n}")
    print("done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
