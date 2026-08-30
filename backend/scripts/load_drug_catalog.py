"""Load the searchable medicine catalogue (Step 3 — pick your medication).

Reads ``drug_classes.csv`` (one row per medicine_id x active_ingredient) from the
static dataset and collapses it to one row per ``product_name`` — the brand name
a user recognises — with its salt composition and the distinct active
ingredients / drug classes joined. Backs ``GET /drugs/search``.

Deploy step — run once after ``alembic upgrade head`` and again whenever the CSV
changes. ``TRUNCATE``s ``drug_catalog``, so run it with the OWNER credentials
(``DATABASE_URL`` / ``POSTGRES_*``), same as migrations and load_risk_tables.

    python -m scripts.load_drug_catalog            # from backend/, venv active
    python -m scripts.load_drug_catalog --data-dir /path/to/data_prep
"""

from __future__ import annotations

import argparse
import csv
import os
import sys

from sqlalchemy import insert, text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import SessionLocal
from app.models import DrugCatalog

_SRC = "drug_classes.csv"
_MAX_NAME = 300
_MAX_SALT = 500
_MAX_JOIN = 500
_MAX_CLASSES = 300


class LoadError(RuntimeError):
    pass


def _clean(s: str | None) -> str:
    return " ".join((s or "").split()).strip()


def _collapse(data_dir: str) -> list[dict]:
    path = os.path.join(data_dir, _SRC)
    if not os.path.exists(path):
        raise LoadError(f"missing CSV: {path}")

    # product_name -> {salt, actives:set, classes:set}
    acc: dict[str, dict] = {}
    with open(path, encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            name = _clean(r.get("product_name"))
            if not name:
                continue
            name = name[:_MAX_NAME]
            e = acc.setdefault(
                name, {"salt": "", "actives": set(), "classes": set()}
            )
            salt = _clean(r.get("salt_composition"))
            if salt and not e["salt"]:
                e["salt"] = salt[:_MAX_SALT]
            ai = _clean(r.get("active_ingredient")).lower()
            if ai:
                e["actives"].add(ai)
            dc = _clean(r.get("drug_class"))
            if dc and dc.lower() not in {"", "unknown", "unclassified"}:
                e["classes"].add(dc)

    rows: list[dict] = []
    for name, e in acc.items():
        actives = ", ".join(sorted(e["actives"]))[:_MAX_JOIN] or None
        classes = ", ".join(sorted(e["classes"]))[:_MAX_CLASSES] or None
        rows.append(
            {
                "product_name": name,
                "salt_composition": e["salt"] or None,
                "active_ingredients": actives,
                "drug_classes": classes,
            }
        )
    return rows


def load(db: Session, data_dir: str) -> int:
    rows = _collapse(data_dir)
    db.execute(text("TRUNCATE TABLE drug_catalog RESTART IDENTITY"))
    for i in range(0, len(rows), 2000):
        db.execute(insert(DrugCatalog), rows[i : i + 2000])
    db.commit()
    return len(rows)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data-dir", default=settings.risk_data_path)
    args = ap.parse_args(argv)

    db = SessionLocal()
    try:
        n = load(db, args.data_dir)
    except LoadError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    finally:
        db.close()
    print(f"loaded {n} medicines into drug_catalog from {args.data_dir}/{_SRC}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
