"""Barcode -> product lookup payloads (Phase 4.1)."""

from __future__ import annotations

import datetime as dt

from pydantic import BaseModel, Field, field_validator


class ProductOut(BaseModel):
    barcode: str
    name: str | None = None
    brand: str | None = None
    ingredients: list[str] = Field(default_factory=list)
    ingredients_text: str | None = None
    nutriments: dict = Field(
        default_factory=dict, description="Normalised nutrition per 100 g (e.g. sugars_g_100g)."
    )
    serving_size: str | None = None
    image_url: str | None = None
    source: str = "openfoodfacts"
    refreshed_at: dt.datetime = Field(description="When this was last fetched from the source.")
    cached: bool = Field(description="True when served from our DB without a fresh upstream call.")
    stale: bool = Field(
        default=False,
        description="True when the source was unreachable and an expired cache entry was served.",
    )


class ProductNotFoundOut(BaseModel):
    detail: str
    barcode: str
    fallback: str = Field(
        default="ocr",
        description="What the client should do instead — 'ocr' = scan the ingredients list.",
    )


class LabelScanOut(BaseModel):
    """Result of OCR-ing a photo of an ingredients list (the fallback for
    products not in Open Food Facts)."""

    ingredients: list[str] = Field(
        default_factory=list,
        description="Best-effort parse into individual ingredient strings — a DRAFT.",
    )
    raw_text: str = Field(description="Sanitised OCR text, so the user can fix parse errors.")
    raw_text_truncated: bool = False
    ocr_confidence: float = Field(
        ge=0.0, le=1.0, description="Mean OCR word confidence (0–1)."
    )
    low_confidence: bool = Field(
        default=False,
        description="True when the scan is unreliable (blurry / rotated / dim, or "
        "nothing parseable) — the client should warn the user, not proceed silently.",
    )
    note: str | None = Field(
        default=None, description="Plain-language advice shown when low_confidence is true."
    )
    editable: bool = Field(
        default=True,
        description="Always true — OCR output must be user-corrected before it's used.",
    )
    source: str = "ocr"


# --------------------------------------------------------------------------- #
# ingredient risk resolution (Phase 4.3)
# --------------------------------------------------------------------------- #
class ResolveRisksIn(BaseModel):
    """A raw ingredient list (from a 4.1 barcode lookup or a 4.2 label scan),
    plus optional per-100 g nutriments for the numeric-threshold pass."""

    ingredients: list[str] = Field(
        default_factory=list, max_length=400,
        description="Ingredient strings — already split, or one run-on string per entry.",
    )
    nutriments: dict[str, float] = Field(
        default_factory=dict,
        description="Normalised per-100 g nutriments (same keys as GET /products/{barcode}).",
    )
    barcode: str | None = Field(default=None, max_length=14)
    product_name: str | None = Field(default=None, max_length=200)

    @field_validator("ingredients")
    @classmethod
    def _cap_each(cls, v: list[str]) -> list[str]:
        return [str(x)[:200] for x in v if str(x).strip()]


class IngredientRiskOut(BaseModel):
    input_text: str
    clean_text: str
    risk_compounds: list[str] = Field(default_factory=list)
    method: str = Field(description="keyword | llm | benign | unverified")
    confidence: float | None = None


class ProductRiskTagOut(BaseModel):
    risk_compound: str
    nutrient_key: str
    value: float
    threshold: float
    confidence: float
    method: str = "threshold"
    rationale: str | None = None


class RiskResolutionOut(BaseModel):
    ingredients: list[IngredientRiskOut] = Field(default_factory=list)
    product_tags: list[ProductRiskTagOut] = Field(default_factory=list)
    risk_compounds: dict[str, float] = Field(
        default_factory=dict,
        description="Union of resolved compounds -> max confidence. Phase 4.4 scores this.",
    )
    unverified: list[str] = Field(
        default_factory=list,
        description="Cleaned ingredient texts the static tables could not confirm.",
    )
    unverified_count: int = 0
    caution_factors: list[str] = Field(
        default_factory=list,
        description="Human-readable cautions 4.4 must surface — includes the "
        "'couldn't confirm N ingredient(s)' line when any ingredient is unverified.",
    )
    resolved_count: int = 0
    benign_count: int = 0
