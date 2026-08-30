"""Load the everyday-food dataset for ``GET /foods/search``.

Two sources, one table (``food_catalog``):
  * ``indian_food.csv``            — home dishes (name, ingredients, diet,
                                      course, region; no nutrition)
  * ``packaged_foods_india.csv``   — branded packaged products with a full
                                      nutrition panel, normalised to per-100 g
                                      and keyed like the Open Food Facts cache

Deploy step — run after ``alembic upgrade head`` and whenever the CSVs change.
``TRUNCATE``s ``food_catalog``, so run it with the OWNER credentials, same as
migrations / the other loaders.

    python -m scripts.load_food_catalog            # from backend/, venv active
    python -m scripts.load_food_catalog --data-dir /path/to/dataset
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys

from sqlalchemy import insert, text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import SessionLocal
from app.models import FoodCatalog

_DISHES = "indian_food.csv"
_PACKAGED = "packaged_foods_india.csv"

# packaged CSV column -> per-100 g key (same vocabulary as the OFF product cache)
_NUTRIENT_MAP = {
    "Calories_kcal": "energy_kcal_100g",
    "Total_Fat_g": "fat_g_100g",
    "Saturated_Fat_g": "saturated_fat_g_100g",
    "Carbohydrates_g": "carbohydrates_g_100g",
    "Sugar_g": "sugars_g_100g",
    "Dietary_Fiber_g": "fiber_g_100g",
    "Proteins_g": "protein_g_100g",
    "Sodium_mg": "sodium_mg_100g",
}

_BAD_CHARS = re.compile("[\x00-\x1f\x7f\x80-\x9f�]")


class LoadError(RuntimeError):
    pass


def _clean(s: str | None, *, limit: int = 300) -> str | None:
    v = " ".join(_BAD_CHARS.sub("", s or "").split()).strip(" ,;\"'")
    if not v or v == "-1":
        return None
    return v[:limit]


def _num(s: str | None) -> float | None:
    try:
        v = float(str(s).strip())
    except (TypeError, ValueError):
        return None
    return None if v < 0 else v


def _rows(path: str) -> list[dict]:
    if not os.path.exists(path):
        raise LoadError(f"missing CSV: {path}")
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def _dishes(data_dir: str) -> list[dict]:
    out = []
    for r in _rows(os.path.join(data_dir, _DISHES)):
        name = _clean(r.get("name"))
        if not name:
            continue
        out.append(
            {
                "name": name,
                "kind": "dish",
                "brand": None,
                "category": _clean(r.get("course"), limit=200),
                "ingredients_text": _clean(r.get("ingredients"), limit=1000),
                "diet": _clean(r.get("diet"), limit=40),
                "course": _clean(r.get("course"), limit=60),
                "region": _clean(r.get("region"), limit=60),
                "serving_size": None,
                "nutriments": {},
            }
        )
    return out


def _packaged(data_dir: str) -> list[dict]:
    out = []
    for r in _rows(os.path.join(data_dir, _PACKAGED)):
        name = _clean(r.get("Item name"))
        if not name:
            continue
        serving = _num(r.get("Serving_Size_g")) or 100.0
        scale = 100.0 / serving if serving else 1.0
        nutr: dict[str, float] = {}
        for col, key in _NUTRIENT_MAP.items():
            v = _num(r.get(col))
            if v is not None:
                nutr[key] = round(v * scale, 2)
        cat = " / ".join(
            p for p in (_clean(r.get("Category"), limit=90),
                        _clean(r.get("Sub_Category"), limit=90)) if p
        ) or None
        out.append(
            {
                "name": name,
                "kind": "packaged",
                "brand": _clean(r.get("Brand_Name"), limit=200),
                "category": cat,
                "ingredients_text": _clean(r.get("Ingredients"), limit=2000),
                "diet": None,
                "course": None,
                "region": None,
                "serving_size": f"{serving:g} g" if serving else None,
                "nutriments": nutr,
            }
        )
    return out


def load(db: Session, data_dir: str) -> dict[str, int]:
    dishes = _dishes(data_dir)
    packaged = _packaged(data_dir)
    db.execute(text("TRUNCATE TABLE food_catalog RESTART IDENTITY"))
    rows = dishes + packaged
    for i in range(0, len(rows), 1000):
        db.execute(insert(FoodCatalog), rows[i : i + 1000])
    db.commit()
    return {"dishes": len(dishes), "packaged": len(packaged), "total": len(rows)}


def main(argv: list[str] | None = None) -> int:
    default_dir = os.path.dirname(settings.risk_data_path)  # .../dataset
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data-dir", default=default_dir)
    args = ap.parse_args(argv)

    db = SessionLocal()
    try:
        counts = load(db, args.data_dir)
    except LoadError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    finally:
        db.close()
    print(
        f"loaded {counts['total']} foods into food_catalog "
        f"({counts['dishes']} dishes + {counts['packaged']} packaged) "
        f"from {args.data_dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
