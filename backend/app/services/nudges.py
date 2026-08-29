"""Behavioural nudge detector (Phase 5.3).

Rule-based, runs right after each new ``scan_history`` row is written: if the
user has **>= 3 non-safe scans (avoid / caution) that share the same recurring
``factor``** (a ``risk_compound`` such as ``sodium``) inside a rolling 14-day
window, and there isn't already a live nudge for that factor, generate one
``Nudge`` row with a **specific, actionable** message (per-factor template — the
count and a concrete swap, never a generic "be careful").
"""

from __future__ import annotations

import datetime as dt

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Nudge, RiskCompound, ScanHistory

WINDOW_DAYS = 14
MIN_HITS = 3

# factor -> template. `{n}` = distinct non-safe scans in the window, `{days}` = 14.
_TEMPLATES: dict[str, str] = {
    "sodium": (
        "Sodium was flagged in {n} of your last {days} days of scans. Next shop: "
        "pick a low-sodium namkeen or unsalted roasted nuts, rinse canned pulses "
        "before cooking, and leave out the seasoning sachet in instant noodles."
    ),
    "added_sugar": (
        "Added sugar came up in {n} scans in {days} days. Swap sweetened / "
        "flavoured yoghurt and milk for plain, and treat 'no added sugar' fruit "
        "juice as a sugary drink — dilute it or switch to whole fruit."
    ),
    "rapid_carb": (
        "Refined-carb items were flagged {n} times in {days} days. Look for the "
        "millet or whole-wheat version of the same product — atta noodles, "
        "multigrain rusk, brown poha, hand-pounded rice."
    ),
    "saturated_fat": (
        "Saturated fat has been high in {n} recent scans. Choose products that "
        "list sunflower or rice-bran oil instead of palm oil / vanaspati, and "
        "pick baked snacks over fried."
    ),
    "trans_fat": (
        "Trans fat / partially-hydrogenated oil showed up in {n} recent scans. "
        "Avoid anything listing 'vanaspati' or 'hydrogenated vegetable fat' — a "
        "product made with plain 'edible vegetable oil' is the safer shelf-mate."
    ),
    "vitamin_k": (
        "{n} leafy-green / vitamin-K products in {days} days. On a vitamin-K-"
        "antagonist blood thinner that's fine *if it stays consistent* — keep "
        "your greens roughly the same amount each week rather than a big swing, "
        "and flag the change at your next INR check."
    ),
    "potassium": (
        "Potassium came up in {n} recent scans. If you're on an ACE inhibitor, "
        "ARB or potassium-sparing diuretic, go easy on coconut water, banana "
        "chips, tomato paste and 'low-sodium' (potassium-chloride) salt."
    ),
    "caffeine": (
        "Caffeine was flagged {n} times in {days} days. Keep it near 2 cups a "
        "day and at a steady time — and remember one energy drink often equals "
        "two coffees."
    ),
    "tyramine": (
        "{n} aged / fermented (tyramine) items in {days} days. On an MAOI-type "
        "medicine (linezolid included) that's worth cutting — aged cheese, "
        "tank / 'draught' beer, soy sauce and cured meats are the usual ones."
    ),
    "milk_allergen": (
        "Milk-derived ingredients keep appearing ({n} in {days} days). Check for "
        "hidden dairy — 'milk solids', casein, whey, ghee — and keep a fortified "
        "soy or oat staple on hand for the swaps."
    ),
    "gluten_allergen": (
        "Wheat / gluten showed up in {n} recent scans. Naturally gluten-free "
        "swaps for the same job: besan or jowar for maida, rice / millet "
        "noodles, roasted chana instead of wheat namkeen."
    ),
    "nut_allergen": (
        "Nut-allergen ingredients were flagged {n} times in {days} days. Watch "
        "'may contain' lines and mixed 'dry fruit' blends; roasted chana or "
        "makhana are safe crunchy swaps."
    ),
    "alcohol": (
        "Alcohol as an ingredient came up in {n} scans in {days} days. With "
        "metronidazole / tinidazole, or on top of sedatives, cut it out — "
        "including in sauces and some kheer / cake flavourings."
    ),
}
_GENERIC = (
    "'{label}' has been flagged in {n} of your last {days} days of scans. "
    "Worth swapping that group for a lower-risk alternative on your next shop."
)


def _render(factor: str, label: str, n: int) -> str:
    return _TEMPLATES.get(factor, _GENERIC).format(n=n, days=WINDOW_DAYS, label=label)


def _label_for(db: Session, factor: str) -> str:
    name = db.scalar(
        select(RiskCompound.display_name).where(RiskCompound.risk_compound == factor)
    )
    return name or factor.replace("_", " ")


def detect_and_record(db: Session, user_id) -> list[Nudge]:
    """Look at the user's non-safe scans in the rolling window, group by
    ``factor``, and create a nudge for any factor at / over the threshold that
    doesn't already have one in the window. Returns the newly-created nudges
    (flushed, not committed — the caller owns the transaction)."""
    now = dt.datetime.now(dt.UTC)
    since = now - dt.timedelta(days=WINDOW_DAYS)

    rows = db.scalars(
        select(ScanHistory).where(
            ScanHistory.user_id == user_id,
            ScanHistory.tier.in_(("avoid", "caution")),
            ScanHistory.scanned_at >= since,
        )
    ).all()

    # one scan contributes at most 1 to each factor's count
    per_factor: dict[str, int] = {}
    for r in rows:
        seen: set[str] = set()
        for kr in r.key_reasons or []:
            f = kr.get("factor")
            if f and f not in seen:
                seen.add(f)
                per_factor[f] = per_factor.get(f, 0) + 1

    created: list[Nudge] = []
    for factor, n in sorted(per_factor.items()):
        if n < MIN_HITS:
            continue
        already = db.scalar(
            select(Nudge.id)
            .where(
                Nudge.user_id == user_id,
                Nudge.factor == factor,
                Nudge.created_at >= since,
            )
            .limit(1)
        )
        if already:
            continue
        nudge = Nudge(
            user_id=user_id,
            factor=factor,
            message=_render(factor, _label_for(db, factor), n),
            hit_count=n,
            window_days=WINDOW_DAYS,
        )
        db.add(nudge)
        created.append(nudge)

    if created:
        db.flush()
    return created
