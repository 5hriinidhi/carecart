"""Response models for GET /drugs/search."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class DrugHit(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    name: str
    salt_composition: str | None = None
    active_ingredients: str | None = None
    drug_classes: str | None = None


class DrugSearchOut(BaseModel):
    query: str
    results: list[DrugHit]
