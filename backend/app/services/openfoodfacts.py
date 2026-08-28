"""Open Food Facts client + normaliser.

The route caches every result (hit or miss) in the ``products`` table for
``product_cache_ttl_hours`` (>= 24h), so this module is only hit on a cache
miss / stale entry - which is what keeps us inside OFF's rate limits.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

import httpx

from app.core.config import settings

logger = logging.getLogger("carecart.off")

# fields we ask OFF for - keeps the payload small
_FIELDS = ",".join(
    [
        "code",
        "product_name",
        "brands",
        "ingredients_text",
        "ingredients",
        "nutriments",
        "serving_size",
        "image_front_small_url",
        "quantity",
    ]
)


class OpenFoodFactsError(RuntimeError):
    """OFF was unreachable / returned an error we can't interpret."""


@dataclass
class NormalizedProduct:
    barcode: str
    name: str | None = None
    brand: str | None = None
    ingredients_text: str | None = None
    ingredients: list[str] = field(default_factory=list)
    nutriments: dict = field(default_factory=dict)
    serving_size: str | None = None
    image_url: str | None = None


def fetch_product(barcode: str) -> dict | None:
    """Return the OFF ``product`` dict, or ``None`` if OFF has no such barcode.

    Raises :class:`OpenFoodFactsError` on a network problem or an unexpected
    upstream response - the caller decides whether to serve stale cache or 502.
    """
    url = f"{settings.off_base_url}/api/v2/product/{barcode}.json"
    try:
        resp = httpx.get(
            url,
            params={"fields": _FIELDS},
            headers={"User-Agent": settings.off_user_agent},
            timeout=settings.off_timeout_seconds,
        )
    except httpx.HTTPError as exc:
        logger.warning("OFF request failed for %s: %s", barcode, exc.__class__.__name__)
        raise OpenFoodFactsError("open food facts unreachable") from exc

    if resp.status_code == 404:
        return None
    if resp.status_code >= 500:
        logger.warning("OFF %s for %s", resp.status_code, barcode)
        raise OpenFoodFactsError(f"open food facts returned {resp.status_code}")

    try:
        body = resp.json()
    except ValueError as exc:
        raise OpenFoodFactsError("open food facts returned a non-JSON body") from exc

    # v2: status 1 = found, 0 = not found
    if body.get("status") == 0 or "product" not in body:
        return None
    return body["product"]


# --------------------------------------------------------------------- normalise
_NUTRIENT_MAP = {
    # our key            (OFF key,               unit conversion)
    "energy_kcal_100g": ("energy-kcal_100g", 1.0),
    "sugars_g_100g": ("sugars_100g", 1.0),
    "salt_g_100g": ("salt_100g", 1.0),
    "sodium_mg_100g": ("sodium_100g", 1000.0),  # OFF gives sodium in g -> mg
    "saturated_fat_g_100g": ("saturated-fat_100g", 1.0),
    "fat_g_100g": ("fat_100g", 1.0),
    "protein_g_100g": ("proteins_100g", 1.0),
    "carbohydrates_g_100g": ("carbohydrates_100g", 1.0),
    "fiber_g_100g": ("fiber_100g", 1.0),
}


def _as_float(value) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _ingredient_list(product: dict) -> list[str]:
    structured = product.get("ingredients")
    if isinstance(structured, list) and structured:
        names = [str(i.get("text", "")).strip() for i in structured if i.get("text")]
        if names:
            return names
    text = (product.get("ingredients_text") or "").strip()
    if not text:
        return []
    # crude fallback split; good enough for display + downstream matching
    parts = [p.strip(" .;") for chunk in text.split(",") for p in chunk.split(";")]
    return [p for p in parts if p]


def normalize(barcode: str, product: dict) -> NormalizedProduct:
    brands = (product.get("brands") or "").split(",")
    nutr_in = product.get("nutriments") or {}
    nutriments = {}
    for out_key, (off_key, factor) in _NUTRIENT_MAP.items():
        val = _as_float(nutr_in.get(off_key))
        if val is not None:
            nutriments[out_key] = round(val * factor, 3)

    return NormalizedProduct(
        barcode=barcode,
        name=(product.get("product_name") or "").strip() or None,
        brand=brands[0].strip() or None if brands and brands[0].strip() else None,
        ingredients_text=(product.get("ingredients_text") or "").strip() or None,
        ingredients=_ingredient_list(product),
        nutriments=nutriments,
        serving_size=(product.get("serving_size") or "").strip() or None,
        image_url=(product.get("image_front_small_url") or "").strip() or None,
    )
