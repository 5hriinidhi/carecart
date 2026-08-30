"""Response models for GET /foods/search."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class FoodHit(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    name: str
    kind: str  # dish | packaged
    brand: str | None = None
    category: str | None = None
    ingredients_text: str | None = None
    diet: str | None = None
    course: str | None = None
    region: str | None = None
    serving_size: str | None = None
    nutriments: dict = {}


class FoodSearchOut(BaseModel):
    query: str
    results: list[FoodHit]
