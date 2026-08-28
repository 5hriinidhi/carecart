"""Resolve a raw ingredient list -> ``risk_compound`` tags, offline (Phase 4.3).

Everything here is a lookup against the pre-built STATIC tables that
``scripts/load_risk_tables.py`` loads into Postgres from
``dataset/data_prep/*.csv``:

* ``ingredient_risk_aliases`` - the ``alias -> risk_compound`` keyword dictionary
  (hand-authored ``ingredient_aliases.csv``) merged with the reviewed LLM
  fallback (``llm_ingredient_tags.csv``, stored as ``match_type='exact'`` rows;
  a NULL ``risk_compound`` row = a token reviewed as carrying no risk compound).
* ``risk_nutrient_thresholds`` - the numeric-threshold counterpart: a per-100 g
  nutrient level at/above which a compound applies to the whole product.

**No LLM / network call happens on this path, ever.** An ingredient that matches
nothing is returned as ``method="unverified"`` (never silently dropped, never
silently treated as safe) and written to the ``unresolved_ingredients`` queue
for the offline batch job to classify later.

The matching logic (segment cleaning, alias matching, negation, coconut/bean
suppression) is a direct port of the one-time data-prep tagger
(``dataset/data_prep/03_tag_foods.py``) so runtime tags line up with the
precomputed ``food_risk_tags.csv``.
"""

from __future__ import annotations

import datetime as dt
import re
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.models import IngredientRiskAlias, RiskNutrientThreshold, UnresolvedIngredient

# --------------------------------------------------------------------------- #
# segment cleaning  (ported from data_prep/03_tag_foods.py)
# --------------------------------------------------------------------------- #
_ADDITIVE_PREFIXES = [
    "artificial flavouring substances", "nature identical flavouring substances",
    "natural flavouring substances", "natural and artificial flavour",
    "natural & artificial flavour", "flavouring substances", "flavour enhancer",
    "flavor enhancer", "acidity regulator", "raising agent", "raising agents",
    "anticaking agent", "anti-caking agent", "anti caking agent", "emulsifying salt",
    "emulsifier", "emulsifiers", "stabiliser", "stabilizer", "stabilisers",
    "stabilizers", "preservative", "preservatives", "class ii preservative",
    "class i preservative", "antioxidant", "antioxidants", "humectant", "sequestrant",
    "thickener", "thickeners", "thickening agent", "gelling agent", "bulking agent",
    "glazing agent", "firming agent", "flour treatment agent", "added colour",
    "added color", "natural colour", "natural color", "synthetic food colour",
    "artificial colour", "food colour", "colour", "color", "permitted",
    "may contain", "contains", "ins", "e",
]
_ENUM_RE = re.compile(r"\b(?:ins|e)?\s*\d{3}[a-z]?(?:\s*\([ivx]+\))?\b", re.I)
_PCT_RE = re.compile(r"\d+(?:\.\d+)?\s*%")
_NUM_RE = re.compile(r"\b\d+(?:\.\d+)?\b")
_ROMAN_RE = re.compile(r"\b[ivx]{1,4}\b", re.I)
_WS_RE = re.compile(r"\s+")
_SPLIT_RE = re.compile(r"[,\(\)\[\]\{\}:;/]|\band\b|\bwith\b|\bfrom\b|&")

_NEGATION_RE = re.compile(
    r"(sugar[-\s]?free|no added sugar|salt[-\s]?free|unsalted|no added salt|"
    r"fat[-\s]?free|gluten[-\s]?free|dairy[-\s]?free|milk[-\s]?free|"
    r"caffeine[-\s]?free|alcohol[-\s]?free|nut[-\s]?free|egg[-\s]?free)"
)
_NEG_MAP = {
    "sugar": "added_sugar", "salt": "sodium", "fat": "saturated_fat",
    "gluten": "gluten_allergen", "dairy": "milk_allergen", "milk": "milk_allergen",
    "caffeine": "caffeine", "alcohol": "alcohol", "nut": "nut_allergen",
    "egg": "egg_allergen", "unsalted": "sodium",
}
_SPECIAL_SUPPRESS = [
    (re.compile(r"\bbean\b"), {"purine"}),
    (re.compile(r"\bkidney bean\b"), {"purine"}),
    (re.compile(r"\bcoconut\b"), {"nut_allergen"}),
]

# genuinely benign / too-generic - not worth an LLM pass or an "unverified" flag
_BENIGN = {
    "water", "aqua", "air", "nitrogen", "carbon dioxide", "edible common salt",
    "common salt", "spices", "spice", "mixed spices", "spices and condiments",
    "condiments", "spice extract", "spice extracts", "seasoning", "herbs",
    "turmeric", "haldi", "chilli", "red chilli", "chilli powder", "coriander",
    "coriander powder", "cumin", "jeera", "mustard", "mustard seed", "curry leaf",
    "curry leaves", "asafoetida", "hing", "ginger", "garlic", "onion",
    "green chilli", "cardamom", "elaichi", "clove", "cinnamon", "dalchini",
    "bay leaf", "tej patta", "black pepper", "white pepper", "pepper", "saffron",
    "kesar", "nutmeg", "mace", "javitri", "fennel", "saunf", "carom", "ajwain",
    "fenugreek", "fenugreek seed", "kalonji", "nigella", "star anise", "anise",
    "tamarind", "imli", "kokum", "amchur", "dry mango powder", "mango powder",
    "rose water", "kewra", "vanilla", "vanillin", "yeast", "iodised salt",
    "iodized salt", "salt", "permitted class", "natural flavour", "natural flavours",
    "natural flavor", "flavour", "flavor", "flavours", "flavors", "colour", "color",
    "edible starch", "cocoa", "cocoa solids", "cocoa powder", "curry powder",
    "garam masala", "masala", "mint", "pudina", "lemon", "lime", "citric acid",
    "salt (iodised)",
}


def clean_ingredient(segment: str) -> str:
    """Normalise one ingredient string (lowercase, drop %/E-numbers/digits, strip
    additive prefixes). Same transform the data-prep tagger applies."""
    s = (segment or "").lower().strip()
    s = _PCT_RE.sub(" ", s)
    s = _ENUM_RE.sub(" ", s)
    s = s.replace(".", " ").replace("'", " ").replace('"', " ").replace("*", " ")
    s = _NUM_RE.sub(" ", s)
    s = _WS_RE.sub(" ", s).strip(" -–—_")
    for _ in range(3):
        for p in _ADDITIVE_PREFIXES:
            if s == p or s.startswith(p + " "):
                s = s[len(p):].strip(" -–—_:")
                break
        else:
            break
    s = _ROMAN_RE.sub(" ", s)
    s = _WS_RE.sub(" ", s).strip(" -–—_")
    return s


def split_ingredient_text(text: str) -> list[str]:
    """Best-effort split of a raw ingredient blob into segments. Callers that
    already have a list (Phase 4.1 / 4.2) still pass through this so a single
    run-on element (``"sugar and milk solids"``) is broken up consistently."""
    if not text or str(text).strip().lower() in ("nan", "none", ""):
        return []
    raw = str(text).replace("\n", " ")
    return [x.strip() for x in _SPLIT_RE.split(raw) if x and x.strip()]


# --------------------------------------------------------------------------- #
# result types
# --------------------------------------------------------------------------- #
@dataclass
class IngredientRisk:
    input_text: str
    clean_text: str
    risk_compounds: list[str]
    method: str                 # keyword | llm | benign | unverified
    confidence: float | None


@dataclass
class ProductRiskTag:
    risk_compound: str
    nutrient_key: str
    value: float
    threshold: float
    confidence: float
    method: str                 # threshold
    rationale: str | None


@dataclass
class RiskResolution:
    ingredients: list[IngredientRisk] = field(default_factory=list)
    product_tags: list[ProductRiskTag] = field(default_factory=list)
    # union of every resolved compound -> its highest confidence. This is what
    # Phase 4.4 severity scoring consumes.
    risk_compounds: dict[str, float] = field(default_factory=dict)
    unverified: list[str] = field(default_factory=list)
    caution_factors: list[str] = field(default_factory=list)

    @property
    def unverified_count(self) -> int:
        return len(self.unverified)

    @property
    def has_unverified(self) -> bool:
        return bool(self.unverified)

    @property
    def resolved_count(self) -> int:
        return sum(1 for i in self.ingredients if i.method in ("keyword", "llm"))

    @property
    def benign_count(self) -> int:
        return sum(1 for i in self.ingredients if i.method == "benign")


# --------------------------------------------------------------------------- #
# reference-table access
# --------------------------------------------------------------------------- #
@dataclass
class _AliasTables:
    keyword: list[tuple[str, str, str, float]]        # (alias, rc, match_type, confidence)
    llm_tags: dict[str, list[tuple[str, float]]]      # clean_text -> [(rc, confidence)]
    llm_reviewed: set[str]                            # clean_texts seen (incl. benign)


def _load_alias_tables(db: Session) -> _AliasTables:
    keyword: list[tuple[str, str, str, float]] = []
    llm_tags: dict[str, list[tuple[str, float]]] = {}
    llm_reviewed: set[str] = set()

    rows = db.execute(
        select(
            IngredientRiskAlias.alias,
            IngredientRiskAlias.risk_compound,
            IngredientRiskAlias.match_type,
            IngredientRiskAlias.confidence,
        )
    ).all()
    for alias, rc, match_type, conf in rows:
        alias = (alias or "").strip().lower()
        if not alias:
            continue
        if match_type == "exact":
            llm_reviewed.add(alias)
            if rc:
                llm_tags.setdefault(alias, []).append((rc, conf if conf is not None else 0.5))
        elif rc:
            keyword.append((alias, rc, match_type, conf if conf is not None else 0.9))
    # longer aliases first so "refined palm oil" wins over "palm oil"
    keyword.sort(key=lambda t: len(t[0]), reverse=True)
    return _AliasTables(keyword=keyword, llm_tags=llm_tags, llm_reviewed=llm_reviewed)


def _match_keyword(raw_seg: str, clean: str, aliases: _AliasTables) -> dict[str, float]:
    """rc -> confidence from the keyword alias table (with negation + suppression)."""
    hay = " " + raw_seg.lower() + " | " + clean + " "
    hits: dict[str, float] = {}
    for alias, rc, mtype, conf in aliases.keyword:
        if mtype == "word":
            if re.search(r"\b" + re.escape(alias) + r"\b", hay):
                hits[rc] = max(hits.get(rc, 0.0), conf)
        elif alias in hay:
            hits[rc] = max(hits.get(rc, 0.0), conf)
    for m in _NEGATION_RE.finditer(hay):
        token = m.group(1)
        for k, rc in _NEG_MAP.items():
            if k in token:
                hits.pop(rc, None)
    for rx, drop in _SPECIAL_SUPPRESS:
        if rx.search(hay):
            for rc in drop:
                hits.pop(rc, None)
    return hits


# --------------------------------------------------------------------------- #
# unresolved-ingredient queue
# --------------------------------------------------------------------------- #
def _enqueue_unresolved(db: Session, ingredient_text: str, normalized: str,
                        sample_product: str | None) -> None:
    """Upsert into the queue: first sighting inserts, repeats bump ``times_seen``
    / ``last_seen_at`` on the same row (unique on ``normalized_text``)."""
    now = dt.datetime.now(dt.UTC)
    sample = sample_product[:200] if sample_product else None
    stmt = (
        pg_insert(UnresolvedIngredient)
        .values(
            ingredient_text=ingredient_text[:200],
            normalized_text=normalized[:200],
            sample_product=sample,
            times_seen=1,
            first_seen_at=now,
            last_seen_at=now,
        )
        .on_conflict_do_update(
            index_elements=["normalized_text"],
            set_={
                "times_seen": UnresolvedIngredient.times_seen + 1,
                "last_seen_at": now,
            },
        )
    )
    db.execute(stmt)


# --------------------------------------------------------------------------- #
# public entry point
# --------------------------------------------------------------------------- #
def resolve_ingredients(
    db: Session,
    ingredients: list[str],
    *,
    nutriments: dict | None = None,
    sample_product: str | None = None,
    queue_unresolved: bool = True,
) -> RiskResolution:
    """Resolve every ingredient string to its ``risk_compound`` tags from the
    static tables. Ingredients that match nothing are marked ``"unverified"`` and
    (unless ``queue_unresolved`` is False) queued for the offline batch job.

    The caller owns the transaction - call ``db.commit()`` afterwards to persist
    any queue writes.
    """
    aliases = _load_alias_tables(db)
    res = RiskResolution()
    seen_clean: set[str] = set()

    # flatten: a caller may pass ["a, b", "c"] or ["a", "b", "c"]
    segments: list[str] = []
    for item in ingredients or []:
        parts = split_ingredient_text(item)
        segments.extend(parts or ([item.strip()] if item and item.strip() else []))

    for raw_seg in segments:
        clean = clean_ingredient(raw_seg)
        if not clean or len(clean) < 2:
            continue
        if clean in seen_clean:
            continue
        seen_clean.add(clean)

        kw = _match_keyword(raw_seg, clean, aliases)
        if kw:
            method, rc_conf = "keyword", kw
        elif clean in aliases.llm_tags:
            method = "llm"
            rc_conf = {}
            for rc, c in aliases.llm_tags[clean]:
                rc_conf[rc] = max(rc_conf.get(rc, 0.0), c)
        elif clean in aliases.llm_reviewed or clean in _BENIGN:
            method, rc_conf = "benign", {}
        elif re.search(r"[a-z]", clean) and len(clean) >= 3:
            method, rc_conf = "unverified", {}
        else:
            method, rc_conf = "benign", {}

        res.ingredients.append(
            IngredientRisk(
                input_text=raw_seg,
                clean_text=clean,
                risk_compounds=sorted(rc_conf),
                method=method,
                confidence=(round(max(rc_conf.values()), 2) if rc_conf else None),
            )
        )
        for rc, c in rc_conf.items():
            res.risk_compounds[rc] = max(res.risk_compounds.get(rc, 0.0), round(c, 2))

        if method == "unverified":
            res.unverified.append(clean)
            if queue_unresolved:
                _enqueue_unresolved(db, raw_seg, clean, sample_product)

    # ---- numeric nutrient thresholds (whole-product tags) ----
    res.product_tags = _resolve_thresholds(db, nutriments or {})
    for tag in res.product_tags:
        res.risk_compounds[tag.risk_compound] = max(
            res.risk_compounds.get(tag.risk_compound, 0.0), round(tag.confidence, 2)
        )

    # ---- caution factors: "unverified" is always surfaced, never swallowed ----
    if res.unverified:
        n = len(res.unverified)
        res.caution_factors.append(
            f"We couldn't confirm {n} ingredient{'s' if n != 1 else ''} in this product."
        )

    return res


def _resolve_thresholds(db: Session, nutriments: dict) -> list[ProductRiskTag]:
    if not nutriments:
        return []
    rows = db.execute(
        select(
            RiskNutrientThreshold.risk_compound,
            RiskNutrientThreshold.nutrient_key,
            RiskNutrientThreshold.min_value,
            RiskNutrientThreshold.confidence,
            RiskNutrientThreshold.method,
            RiskNutrientThreshold.rationale,
        )
    ).all()

    # per (risk_compound, nutrient_key) keep the most specific band that fires
    best: dict[tuple[str, str], ProductRiskTag] = {}
    for rc, key, min_value, conf, method, rationale in rows:
        raw = nutriments.get(key)
        try:
            value = float(raw)
        except (TypeError, ValueError):
            continue
        if value < min_value:
            continue
        cur = best.get((rc, key))
        if cur is None or min_value > cur.threshold:
            best[(rc, key)] = ProductRiskTag(
                risk_compound=rc,
                nutrient_key=key,
                value=round(value, 3),
                threshold=min_value,
                confidence=conf,
                method=method or "threshold",
                rationale=rationale,
            )
    # collapse to the strongest tag per risk_compound (a compound may have >1 key)
    strongest: dict[str, ProductRiskTag] = {}
    for tag in best.values():
        cur = strongest.get(tag.risk_compound)
        if cur is None or tag.confidence > cur.confidence:
            strongest[tag.risk_compound] = tag
    return sorted(strongest.values(), key=lambda t: t.risk_compound)
