"""Scan verdict payloads (Phase 4.4 — food-drug interaction & severity scoring)."""

from __future__ import annotations

from pydantic import BaseModel, Field, field_validator


class ScanVerdictIn(BaseModel):
    """A product's decoded ingredients (from Phase 4.1 / 4.2, optionally already
    passed through 4.3) plus its per-100 g nutriments. The user's conditions,
    allergies and active medications are read server-side from the JWT — never
    sent by the client."""

    ingredients: list[str] = Field(default_factory=list, max_length=400)
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


class VerdictReasonOut(BaseModel):
    kind: str = Field(
        description="allergen | drug_interaction | condition_ceiling | "
        "condition_compound | poor_fit | unverified | clear"
    )
    severity: str = Field(description="high | moderate | low | info")
    points: int = Field(description="Score deducted for this factor (0 for a hard stop / info).")
    title: str
    detail: str | None = None


class MedMatchOut(BaseModel):
    name: str
    drug_classes: list[str] = Field(default_factory=list)
    identified: bool


class ScanVerdictOut(BaseModel):
    score: int = Field(ge=0, le=100)
    tier: str = Field(
        description="safe (>=70) | caution (>=45) | avoid — the exact Phase 2.1 thresholds"
    )
    hard_stop: bool = Field(
        description="True when an allergen match forced 'avoid' regardless of score."
    )
    reasons: list[VerdictReasonOut] = Field(
        default_factory=list,
        description="Plain-language, most-severe-first list of what drove the verdict.",
    )
    medications: list[MedMatchOut] = Field(default_factory=list)
    risk_compounds: dict[str, float] = Field(default_factory=dict)
    unverified: list[str] = Field(default_factory=list)
    unverified_count: int = 0
