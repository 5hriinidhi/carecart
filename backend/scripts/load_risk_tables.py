"""Load the pre-built STATIC risk-reference CSVs into Postgres (Phase 4.3).

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

Reference rows are fully replaced on each run (``TRUNCATE risk_compounds
CASCADE``). The ``unresolved_ingredients`` queue is a runtime table and is
never touched here.
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
    FoodRiskTag,
    IngredientRiskAlias,
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


def load_all(db: Session, data_dir: str) -> dict[str, int]:
    """Replace every reference table from the CSVs in ``data_dir``. Returns row
    counts. Raises :class:`LoadError` on an unknown ``risk_compound`` reference."""
    rc_rows = _rows(os.path.join(data_dir, "risk_compounds.csv"))
    valid_rc = {r["risk_compound"].strip() for r in rc_rows}

    alias_rows = _rows(os.path.join(data_dir, "ingredient_aliases.csv"))
    llm_rows = _rows(os.path.join(data_dir, "llm_ingredient_tags.csv"))
    thr_rows = _rows(os.path.join(data_dir, "risk_nutrient_thresholds.csv"))
    food_rows = _rows(os.path.join(data_dir, "food_risk_tags.csv"))

    problems: list[str] = []

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
        try:
            conf = float(r.get("confidence") or 0) or None
        except ValueError:
            conf = None
        rcs = [x.strip() for x in _RC_SPLIT.split(r.get("risk_compounds", "")) if x.strip()]
        rcs = [x for x in rcs if x not in ("none", "benign", "")]
        if not rcs:
            # token reviewed as carrying no risk compound -> known-benign marker
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

    foods: list[dict] = []
    for r in food_rows:
        rc = r["risk_compound"].strip()
        if rc not in valid_rc:
            problems.append(f"food_risk_tags.csv: {r.get('food_id')} -> unknown '{rc}'")
            continue
        try:
            conf = float(r.get("confidence") or 0) or None
        except ValueError:
            conf = None
        foods.append(
            dict(id=uuid.uuid4(), food_id=r["food_id"].strip(), risk_compound=rc,
                 confidence=conf, method=(r.get("method") or "").strip() or None)
        )

    if problems:
        raise LoadError(
            f"{len(problems)} reference problem(s):\n  " + "\n  ".join(problems[:25])
        )

    # replace everything (CASCADE clears the three child tables too)
    db.execute(text("TRUNCATE TABLE risk_compounds CASCADE"))
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
    db.commit()

    return {
        "risk_compounds": len(rc_rows),
        "ingredient_risk_aliases": len(aliases),
        "  - keyword": sum(1 for a in aliases if a["source"] == "keyword"),
        "  - llm": sum(1 for a in aliases if a["source"] == "llm"),
        "risk_nutrient_thresholds": len(thresholds),
        "food_risk_tags": len(foods),
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
