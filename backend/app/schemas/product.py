"""Barcode -> product lookup payloads (Phase 4.1)."""

from __future__ import annotations

import datetime as dt

from pydantic import BaseModel, Field


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
