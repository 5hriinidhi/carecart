"""Seed a demo backend with a handful of realistic personas + weeks of scan
history, so a judge sees populated trends and live nudges the moment they open
the app — no waiting for usage to accumulate (Phase 6.4).

Personas (the proposal's "User Persona Mindset"):
  * Priya  — Type 2 diabetes + hypertension; watches sugar & sodium. Recurring
             added-sugar nudge.
  * Ravi   — manages his father's meds: on Warfarin (anticoagulant); leafy
             greens & supplements trip vitamin-K interactions. Recurring nudge.
  * Aarav  — tree-nut + dairy allergy; energy bars / chocolate keep hard-stopping.
             Recurring nut-allergen nudge.
  * Meera  — health-optimiser, no conditions; almost everything scans safe.
             Clean, improving trend, no nudge.

Run against the DEMO database (not prod):

    python -m scripts.load_risk_tables          # once, for nudge label lookups
    python -m scripts.seed_demo_products        # once, so live re-scans work
    python -m scripts.seed_demo_users --reset   # idempotent: wipes + reseeds

Prints each persona's phone (the demo backend echoes the OTP in
POST /auth/request-otp because ENVIRONMENT=development) and a ready-to-use
access token.
"""

from __future__ import annotations

import argparse
import datetime as dt
import sys

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core.security import create_access_token, hash_phone
from app.db.session import SessionLocal
from app.models import (
    Allergy,
    Condition,
    HealthProfile,
    Medication,
    ScanHistory,
    User,
)
from app.services import nudges as nudge_svc

_NOW = dt.datetime.now(dt.UTC)


def _r(kind: str, sev: str, title: str, factor: str | None) -> dict:
    return {"kind": kind, "severity": sev, "title": title, "factor": factor}


# a compact reusable set of reasons
_SUGAR = _r("condition_ceiling", "high", "Added sugar over your per-serving ceiling", "added_sugar")
_SODIUM = _r("condition_ceiling", "high", "High sodium for Hypertension", "sodium")
_RAPID = _r("poor_fit", "low", "Refined / rapidly-digested carbs", "rapid_carb")
_VITK = _r("drug_interaction", "high", "Warfarin interacts with Vitamin K", "vitamin_k")
_NUT = _r("allergen", "high", "Contains tree nuts — you told us you're allergic", "nut_allergen")
_MILK = _r("allergen", "high", "Contains milk — you told us you're allergic", "milk_allergen")
_CLEAR = _r("clear", "info", "No conflicts with your medications, conditions or allergies", None)


PERSONAS: list[dict] = [
    {
        "name": "Priya Sharma",
        "phone": "+919000000001",
        "blurb": "Type 2 diabetes + hypertension — watching sugar & sodium",
        "profile": {"gender": "female", "activity_level": "moderate",
                    "body_metrics": {"weight": 68, "height": 162,
                                     "weight_unit": "kg", "height_unit": "cm"},
                    "diet_type": ["low sugar", "low sodium"]},
        "conditions": ["Type 2 diabetes", "Hypertension"],
        "allergies": [],
        "medications": [("Metformin 500mg", "500 mg"), ("Telmisartan 40mg", "40 mg")],
        # (days_ago, product, score, tier, [reasons])
        "scans": [
            (26, "Quaker Rolled Oats", 96, "safe", [_CLEAR]),
            (25, "Britannia Digestive Biscuits", 58, "caution", [_SUGAR]),
            (24, "Real Fruit Juice 200ml", 41, "avoid", [_SUGAR, _RAPID]),
            (22, "Amul Masala Buttermilk", 72, "safe", []),
            (21, "Haldiram Aloo Bhujia", 52, "caution", [_SODIUM]),
            (19, "Cadbury Dairy Milk 40g", 33, "avoid", [_SUGAR]),
            (18, "Whole Wheat Bread", 78, "safe", []),
            (16, "Kissan Mixed Fruit Jam", 38, "avoid", [_SUGAR]),
            (14, "Roasted Chana", 88, "safe", [_CLEAR]),
            (12, "Bourbon Cream Biscuits", 40, "avoid", [_SUGAR]),
            (11, "Nescafe 3-in-1 Sachet", 44, "avoid", [_SUGAR]),
            (9, "Idli Batter", 74, "safe", []),
            (8, "Frooti Mango Drink", 36, "avoid", [_SUGAR, _RAPID]),
            (6, "Marie Gold Biscuits", 55, "caution", [_SUGAR]),
            (5, "Sprouts Salad Bowl", 92, "safe", [_CLEAR]),
            (3, "Parle-G Biscuits", 42, "avoid", [_SUGAR]),
            (2, "Greek Yogurt Unsweetened", 85, "safe", []),
            (1, "Coca-Cola 250ml", 28, "avoid", [_SUGAR, _RAPID]),
        ],
    },
    {
        "name": "Ravi Menon",
        "phone": "+919000000002",
        "blurb": "manages his father's meds — on Warfarin, greens trip vitamin-K",
        "profile": {"gender": "male", "activity_level": "sedentary",
                    "body_metrics": {"weight": 74, "height": 170,
                                     "weight_unit": "kg", "height_unit": "cm"},
                    "diet_type": []},
        "conditions": ["Atrial fibrillation"],
        "allergies": [],
        "medications": [("Warfarin 5mg", "5 mg"), ("Bisoprolol 2.5mg", "2.5 mg")],
        "scans": [
            (20, "Fresh Spinach (Palak)", 55, "caution", [_VITK]),
            (18, "Broccoli Florets", 58, "caution", [_VITK]),
            (17, "Amul Butter", 68, "safe", []),
            (15, "Multivitamin Gummies", 50, "caution", [_VITK]),
            (13, "Toor Dal", 90, "safe", [_CLEAR]),
            (11, "Kale Chips", 46, "avoid", [_VITK]),
            (10, "Brown Rice", 86, "safe", []),
            (8, "Fenugreek Leaves (Methi)", 52, "caution", [_VITK]),
            (6, "Green Tea Bags", 70, "safe", []),
            (4, "Spinach & Corn Sandwich", 48, "avoid", [_VITK]),
            (2, "Curd Rice Ready Meal", 76, "safe", []),
            (1, "Moringa Powder Supplement", 44, "avoid", [_VITK]),
        ],
    },
    {
        "name": "Aarav Iyer",
        "phone": "+919000000003",
        "blurb": "tree-nut + dairy allergy — bars & chocolate keep hard-stopping",
        "profile": {"gender": "male", "activity_level": "heavy",
                    "body_metrics": {"weight": 70, "height": 176,
                                     "weight_unit": "kg", "height_unit": "cm"},
                    "diet_type": ["high protein"]},
        "conditions": [],
        "allergies": ["Tree nuts", "Dairy"],
        "medications": [],
        "scans": [
            (19, "Yogabar Multigrain Bar", 0, "avoid", [_NUT]),
            (17, "Amul Dark Chocolate", 0, "avoid", [_MILK]),
            (15, "Roasted Peanut Butter", 82, "safe", []),
            (13, "Nutcracker Trail Mix", 0, "avoid", [_NUT]),
            (12, "Plain Oats", 94, "safe", [_CLEAR]),
            (10, "Snickers Bar", 0, "avoid", [_NUT, _MILK]),
            (8, "Grilled Chicken Wrap", 88, "safe", []),
            (6, "Almond Energy Bar", 0, "avoid", [_NUT]),
            (4, "Boiled Egg Pack", 91, "safe", [_CLEAR]),
            (2, "Cashew Cookies", 0, "avoid", [_NUT]),
            (1, "Whey Protein Scoop", 79, "safe", []),
        ],
    },
    {
        "name": "Meera Nair",
        "phone": "+919000000004",
        "blurb": "health-optimiser, no conditions — almost everything scans safe",
        "profile": {"gender": "female", "activity_level": "moderate",
                    "body_metrics": {"weight": 59, "height": 165,
                                     "weight_unit": "kg", "height_unit": "cm"},
                    "diet_type": ["low sodium", "vegetarian"]},
        "conditions": [],
        "allergies": [],
        "medications": [],
        "scans": [
            (21, "Rolled Oats", 96, "safe", [_CLEAR]),
            (18, "Mixed Vegetable Salad", 95, "safe", [_CLEAR]),
            (16, "Hummus & Pita", 84, "safe", []),
            (14, "Ragi Malt Drink", 88, "safe", []),
            (12, "Salted Peanuts", 66, "caution", [_SODIUM]),
            (10, "Greek Yogurt", 90, "safe", []),
            (8, "Whole Wheat Pasta", 82, "safe", []),
            (6, "Fruit & Nut Muesli", 79, "safe", []),
            (4, "Vegetable Poha", 92, "safe", [_CLEAR]),
            (2, "Masala Oats Cup", 71, "safe", []),
            (1, "Banana", 97, "safe", [_CLEAR]),
        ],
    },
]


def _seed_persona(db: Session, p: dict) -> dict:
    phash = hash_phone(p["phone"])
    uid = db.scalar(select(User.id).where(User.phone_hash == phash))
    if uid is None:
        u = User(phone_hash=phash, display_name=p["name"].split()[0])
        db.add(u)
        db.flush()
        uid = u.id
    else:
        # wipe this persona's owned rows so a re-run is a clean reseed
        for model in (ScanHistory, Medication, Allergy, Condition, HealthProfile):
            db.execute(delete(model).where(model.user_id == uid))
        db.execute(delete(nudge_svc.Nudge).where(nudge_svc.Nudge.user_id == uid))

    hp = p["profile"]
    db.add(HealthProfile(
        user_id=uid, gender=hp["gender"], activity_level=hp["activity_level"],
        body_metrics=hp["body_metrics"], diet_type=hp["diet_type"],
    ))
    for c in p["conditions"]:
        db.add(Condition(user_id=uid, condition_name=c))
    for a in p["allergies"]:
        db.add(Allergy(user_id=uid, allergen_name=a))
    for name, dose in p["medications"]:
        db.add(Medication(user_id=uid, name=name, dosage=dose))

    for days_ago, product, score, tier, reasons in p["scans"]:
        db.add(ScanHistory(
            user_id=uid,
            product_name=product,
            barcode=None,
            score=score,
            tier=tier,
            hard_stop=any(r["kind"] == "allergen" for r in reasons),
            key_reasons=reasons[:4],
            scanned_at=_NOW - dt.timedelta(days=days_ago, hours=days_ago % 5),
        ))
    db.flush()

    nudges = nudge_svc.detect_and_record(db, uid)
    db.commit()

    return {
        "name": p["name"],
        "phone": p["phone"],
        "blurb": p["blurb"],
        "scans": len(p["scans"]),
        "nudges": [(n.factor, n.hit_count) for n in nudges],
        "token": create_access_token(uid),
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--reset", action="store_true",
                    help="delete the demo users first, then reseed")
    args = ap.parse_args(argv)

    db = SessionLocal()
    try:
        if args.reset:
            hashes = [hash_phone(p["phone"]) for p in PERSONAS]
            n = db.execute(
                delete(User).where(User.phone_hash.in_(hashes))
            ).rowcount
            db.commit()
            print(f"--reset: removed {n} existing demo user(s)")

        results = [_seed_persona(db, p) for p in PERSONAS]
    finally:
        db.close()

    print("\n" + "=" * 74)
    print("  DEMO PERSONAS SEEDED  (log in with the phone; the dev backend")
    print("  echoes the OTP in the POST /auth/request-otp response)")
    print("=" * 74)
    for r in results:
        nud = ", ".join(f"{f}×{c}" for f, c in r["nudges"]) or "none"
        print(f"\n  {r['name']}   {r['phone']}")
        print(f"    {r['blurb']}")
        print(f"    {r['scans']} scans over ~4 weeks   nudge: {nud}")
        print(f"    token: {r['token']}")
    print("\n" + "=" * 74)
    return 0


if __name__ == "__main__":
    sys.exit(main())
