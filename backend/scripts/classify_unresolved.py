"""Offline batch job: drain the ``unresolved_ingredients`` queue (Phase 4.3).

**Not part of the running app.** Run it by hand or on a schedule (weekly / monthly).
Nothing here is ever called on the scan path.

Two steps, deliberately separate so results stay reviewable and are never
auto-trusted:

    # 1. classify the pending queue -> a review CSV (writes NOTHING to the CSVs)
    python -m scripts.classify_unresolved classify --out review_2026-08-28.csv
    #    add --use-api to also try a real Claude call for tokens the curated
    #    map misses (needs CLAUDE_API_KEY; offline-tolerant - falls back to
    #    "unclassified" on any error).

    # 2. a human edits review_*.csv, sets accept = y / n per row, then:
    python -m scripts.classify_unresolved merge --reviewed review_2026-08-28.csv
    #    accepted rows are appended to dataset/data_prep/llm_ingredient_tags.csv
    #    (with method + confidence + rationale, same shape as before) and logged
    #    to food_ingredient_method_log.csv. Queue rows -> status merged / rejected.

After a merge, re-run the data-prep tagger and reload Postgres:

    (cd ../gradient-ascend-mobile-app/project/dataset/data_prep && python 03_tag_foods.py)
    python -m scripts.load_risk_tables

The classifier's default engine is the SAME approach the original data-prep job
used (``make_llm_ingredient_tags.py``): a curated, editable dict of
nutrition / food-chemistry judgements. ``--use-api`` swaps in a live model call
for the misses, exactly as that script's docstring anticipated ("Swap in a real
API call if you want").
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import re
import sys

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models import UnresolvedIngredient

_RC_SPLIT = re.compile(r"[;,|]")

VALID_RISK_COMPOUNDS = {
    "sodium", "potassium", "added_sugar", "rapid_carb", "saturated_fat", "trans_fat",
    "tyramine", "vitamin_k", "grapefruit_furanocoumarin", "caffeine", "oxalate",
    "calcium_mineral_chelation", "alcohol", "histamine", "licorice_glycyrrhizin",
    "purine", "milk_allergen", "soy_allergen", "nut_allergen", "gluten_allergen",
    "egg_allergen", "sesame_allergen", "fish_allergen", "crustacean_shellfish_allergen",
    "mustard_allergen", "sulphite_allergen",
}

REVIEW_FIELDS = [
    "ingredient_text", "normalized_text", "times_seen", "sample_product",
    "risk_compounds", "confidence", "method", "model", "rationale", "accept",
]


# --------------------------------------------------------------------------- #
# engine 1: curated dict  (same approach as make_llm_ingredient_tags.py::MAP)
# --------------------------------------------------------------------------- #
def _g(tokens, rcs, conf, why):
    return {t: (rcs, conf, why) for t in tokens}


_CURATED: dict[str, tuple[str, float | str, str]] = {}
_CURATED.update(_g(
    ["edible vegetable fat", "vegetable fat", "vegetable fats", "palm fat",
     "fractionated fat", "interesterified vegetable fat", "palm kernel oil",
     "sal fat", "vegetable fat powder"],
    "saturated_fat", 0.8, "solid/tropical/interesterified fat - high in saturated fatty acids"))
_CURATED.update(_g(
    ["hydrogenated vegetable fat", "hydrogenated fat", "partially hydrogenated fat"],
    "saturated_fat;trans_fat", 0.7, "hydrogenated fat - saturated, possible residual trans fat"))
_CURATED.update(_g(
    ["edible vegetable oil", "refined vegetable oil", "refined oil"],
    "saturated_fat", 0.4,
    "unspecified 'vegetable oil' in Indian packaged food is frequently palm - low confidence"))
_CURATED.update(_g(
    ["starch", "rice starch", "tapioca flour", "pea starch", "modified tapioca starch"],
    "rapid_carb", 0.7, "refined starch - rapidly digested"))
_CURATED.update(_g(
    ["all purpose flour", "all-purpose flour", "plain flour"],
    "rapid_carb;gluten_allergen", 0.7, "unqualified refined wheat flour"))
_CURATED.update(_g(
    ["hydrolysed vegetable protein", "hydrolyzed vegetable protein", "hvp"],
    "sodium", 0.6, "HVP - manufactured with salt, high free glutamate; sodium load"))
_CURATED.update(_g(
    ["seasoning mix", "seasoning powder", "noodle tastemaker", "tastemaker"],
    "sodium", 0.6, "snack/noodle seasoning - salt + MSG heavy"))
_CURATED.update(_g(
    ["baking powder"], "sodium", 0.6, "baking powder contains sodium bicarbonate"))
_CURATED.update(_g(
    ["khoa", "chhena", "chenna", "milk protein concentrate", "buttermilk powder",
     "cheese powder", "cheese solids"],
    "milk_allergen", 0.85, "milk-derived solid"))
_CURATED.update(_g(
    ["nuts", "mixed nuts", "assorted nuts", "nut mix"],
    "nut_allergen", 0.85, "'nuts' plural / mixed-nut blend"))
_CURATED["eggs"] = ("egg_allergen", 0.95, "plural of egg")
_CURATED.update(_g(
    ["prawn", "prawns", "shrimp", "crab", "lobster", "squid", "shellfish"],
    "crustacean_shellfish_allergen", 0.9, "crustacean / mollusc protein"))
_CURATED.update(_g(
    ["tomato powder", "tomato concentrate", "dried tomato", "sun dried tomato"],
    "potassium", 0.5, "concentrated tomato - notable potassium"))
_CURATED.update(_g(
    ["chocolate", "compound chocolate", "choco chips", "chocolate chips",
     "chocolate coating"],
    "added_sugar;saturated_fat", 0.6, "chocolate/compound coating - sugar plus tropical fat"))
# reviewed, carries no risk compound
for _tok in ["sunflower oil", "rice bran oil", "olive oil", "corn oil",
             "gram flour", "besan", "moong dal", "urad dal", "toor dal",
             "jowar flour", "bajra flour", "ragi flour", "quinoa", "oats",
             "carrot", "peas", "capsicum", "cucumber", "coconut", "pectin",
             "guar gum", "xanthan gum", "carrageenan", "citric acid",
             "ascorbic acid", "sodium bicarbonate"]:
    _CURATED.setdefault(_tok, ("none", "", "reviewed - no food-drug risk compound"))


def _classify_curated(token: str):
    hit = _CURATED.get(token.strip().lower())
    if hit is None:
        return None
    rcs, conf, why = hit
    return (rcs, conf if conf != "" else None, "llm-curated", "", why)


# --------------------------------------------------------------------------- #
# engine 2: live model call (opt-in, offline-tolerant)
# --------------------------------------------------------------------------- #
_API_SYSTEM = (
    "You classify a single food-ingredient string into zero or more risk_compound "
    "tags for a food-drug interaction checker. Valid tags ONLY: "
    + ", ".join(sorted(VALID_RISK_COMPOUNDS))
    + ". Reply with STRICT JSON: {\"risk_compounds\": [..], \"confidence\": 0-0.9, "
    "\"rationale\": \"...\"}. Use [] when the ingredient carries no risk compound. "
    "Never invent a tag outside the list. Never return confidence above 0.9."
)


def _classify_api(token: str, api_key: str, model: str):
    import httpx  # local import: this branch is opt-in tooling, not a runtime dep

    try:
        resp = httpx.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": model,
                "max_tokens": 300,
                "system": _API_SYSTEM,
                "messages": [{"role": "user", "content": f"Ingredient: {token}"}],
            },
            timeout=30.0,
        )
        resp.raise_for_status()
        blocks = resp.json().get("content", [])
        payload = "".join(b.get("text", "") for b in blocks if b.get("type") == "text")
        data = json.loads(payload[payload.index("{") : payload.rindex("}") + 1])
    except Exception as exc:  # noqa: BLE001  offline-tolerant
        print(f"  ! api classify failed for {token!r}: {exc.__class__.__name__}",
              file=sys.stderr)
        return None

    rcs = [str(x).strip() for x in data.get("risk_compounds", []) if str(x).strip()]
    rcs = [x for x in rcs if x in VALID_RISK_COMPOUNDS]
    try:
        conf = max(0.0, min(0.9, float(data.get("confidence", 0.5))))
    except (TypeError, ValueError):
        conf = 0.5
    rationale = str(data.get("rationale", "")).strip()[:300]
    return (";".join(rcs) if rcs else "none", conf if rcs else None,
            "llm-api", model, rationale)


# --------------------------------------------------------------------------- #
# step 1: classify
# --------------------------------------------------------------------------- #
def classify_pending(db: Session, *, min_seen: int = 1, limit: int | None = None,
                     use_api: bool = False, api_key: str = "",
                     model: str = "claude-haiku-4-5-20251001") -> list[dict]:
    q = (
        select(UnresolvedIngredient)
        .where(UnresolvedIngredient.status == "pending",
               UnresolvedIngredient.times_seen >= min_seen)
        .order_by(UnresolvedIngredient.times_seen.desc(),
                  UnresolvedIngredient.first_seen_at)
    )
    if limit:
        q = q.limit(limit)
    rows = db.scalars(q).all()

    out: list[dict] = []
    for row in rows:
        guess = _classify_curated(row.normalized_text)
        if guess is None and use_api and api_key:
            guess = _classify_api(row.normalized_text, api_key, model)
        if guess is None:
            rcs, conf, method, used_model, rationale = "", "", "unclassified", "", ""
        else:
            rcs, conf, method, used_model, rationale = guess
        out.append({
            "ingredient_text": row.ingredient_text,
            "normalized_text": row.normalized_text,
            "times_seen": row.times_seen,
            "sample_product": row.sample_product or "",
            "risk_compounds": rcs,
            "confidence": "" if conf in (None, "") else round(float(conf), 2),
            "method": method,
            "model": used_model,
            "rationale": rationale,
            "accept": "",
        })
        row.status = "classified"

    db.commit()
    return out


def write_review_csv(rows: list[dict], path: str) -> None:
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=REVIEW_FIELDS)
        w.writeheader()
        w.writerows(rows)


# --------------------------------------------------------------------------- #
# step 2: merge reviewed results back into the CSVs
# --------------------------------------------------------------------------- #
_TRUE = {"y", "yes", "1", "true", "accept", "a"}


def merge_reviewed(db: Session, reviewed_path: str, data_dir: str) -> dict[str, int]:
    with open(reviewed_path, encoding="utf-8-sig", newline="") as f:
        reviewed = list(csv.DictReader(f))

    llm_csv = os.path.join(data_dir, "llm_ingredient_tags.csv")
    log_csv = os.path.join(data_dir, "food_ingredient_method_log.csv")

    existing: set[str] = set()
    if os.path.exists(llm_csv):
        with open(llm_csv, encoding="utf-8-sig", newline="") as f:
            existing = {r["ingredient_clean"].strip().lower() for r in csv.DictReader(f)}

    accepted, rejected, skipped = [], [], 0
    for r in reviewed:
        token = (r.get("normalized_text") or r.get("ingredient_text") or "").strip().lower()
        if not token:
            continue
        if (r.get("accept") or "").strip().lower() not in _TRUE:
            rejected.append(token)
            continue
        rcs = [x.strip() for x in _RC_SPLIT.split(r.get("risk_compounds", "")) if x.strip()]
        rcs = [x for x in rcs if x in VALID_RISK_COMPOUNDS] or ["none"]
        if token in existing:
            skipped += 1
            continue
        accepted.append({
            "ingredient_clean": token,
            "risk_compounds": ";".join(rcs),
            "confidence": (r.get("confidence") or "").strip(),
            "method": (r.get("method") or "llm").strip(),
            "rationale": (r.get("rationale") or "").strip(),
        })
        existing.add(token)

    # append accepted rows to llm_ingredient_tags.csv (same schema as before)
    if accepted:
        new_file = not os.path.exists(llm_csv)
        with open(llm_csv, "a", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(
                f, fieldnames=["ingredient_clean", "risk_compounds", "confidence",
                               "method", "rationale"])
            if new_file:
                w.writeheader()
            w.writerows(accepted)
        # audit trail: one line per merged token
        log_new = not os.path.exists(log_csv)
        with open(log_csv, "a", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(
                f, fieldnames=["food_id", "source_file", "ingredient_raw",
                               "ingredient_clean", "risk_compounds", "method"])
            if log_new:
                w.writeheader()
            for a in accepted:
                w.writerow({
                    "food_id": "QUEUE",
                    "source_file": "unresolved_ingredients",
                    "ingredient_raw": a["ingredient_clean"],
                    "ingredient_clean": a["ingredient_clean"],
                    "risk_compounds": "" if a["risk_compounds"] == "none"
                    else a["risk_compounds"],
                    "method": a["method"],
                })

    # reflect outcomes in the queue
    acc_tokens = [a["ingredient_clean"] for a in accepted]
    if acc_tokens:
        db.execute(
            update(UnresolvedIngredient)
            .where(UnresolvedIngredient.normalized_text.in_(acc_tokens))
            .values(status="merged")
        )
    if rejected:
        db.execute(
            update(UnresolvedIngredient)
            .where(UnresolvedIngredient.normalized_text.in_(rejected))
            .values(status="rejected")
        )
    db.commit()

    return {"accepted": len(accepted), "rejected": len(rejected),
            "skipped_already_present": skipped}


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main(argv: list[str] | None = None) -> int:
    from app.core.config import settings

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("classify", help="classify the pending queue -> a review CSV")
    c.add_argument("--min-seen", type=int, default=1)
    c.add_argument("--limit", type=int, default=None)
    c.add_argument("--use-api", action="store_true",
                   help="try a live Claude call for tokens the curated map misses")
    c.add_argument("--model", default="claude-haiku-4-5-20251001")
    c.add_argument("--out", default=f"unresolved_review_{dt.date.today().isoformat()}.csv")

    m = sub.add_parser("merge", help="merge an accept-marked review CSV into the data CSVs")
    m.add_argument("--reviewed", required=True)
    m.add_argument("--data-dir", default=settings.risk_data_path)

    args = ap.parse_args(argv)
    db = SessionLocal()
    try:
        if args.cmd == "classify":
            if args.use_api and not settings.claude_api_key:
                print("--use-api given but CLAUDE_API_KEY is empty; curated map only.",
                      file=sys.stderr)
            rows = classify_pending(
                db, min_seen=args.min_seen, limit=args.limit,
                use_api=args.use_api, api_key=settings.claude_api_key, model=args.model,
            )
            write_review_csv(rows, args.out)
            by_method: dict[str, int] = {}
            for r in rows:
                by_method[r["method"]] = by_method.get(r["method"], 0) + 1
            print(f"classified {len(rows)} queued ingredient(s) -> {args.out}")
            for k, v in sorted(by_method.items()):
                print(f"  {k:<14} {v}")
            print("review the CSV (set accept=y/n), then: "
                  "python -m scripts.classify_unresolved merge --reviewed " + args.out)
            return 0

        counts = merge_reviewed(db, args.reviewed, os.path.abspath(args.data_dir))
        for k, v in counts.items():
            print(f"  {k:<26} {v}")
        print("now re-run 03_tag_foods.py and scripts.load_risk_tables to deploy.")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
