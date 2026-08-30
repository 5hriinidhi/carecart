"""Response model for GET /me/fit (the CareCart Fit score)."""

from __future__ import annotations

from pydantic import BaseModel

from app.services.fit import FitResult


class FitDimOut(BaseModel):
    key: str
    label: str
    score: int
    weight: float
    detail: str


class FitLifestyleOut(BaseModel):
    overall: int | None
    answered: int
    total: int
    dims: list[FitDimOut]


class FitMedItemOut(BaseModel):
    name: str
    identified: bool
    score: int | None
    note: str
    interactions: list[str]


class FitMedicinesOut(BaseModel):
    overall: int | None
    scans_in_window: int
    meds: list[FitMedItemOut]


class FitFocusOut(BaseModel):
    area: str
    key: str
    label: str
    score: int
    message: str


class FitOut(BaseModel):
    score: int | None
    tier: str | None
    delta: int
    lifestyle: FitLifestyleOut
    medicines: FitMedicinesOut
    focus: FitFocusOut | None

    @classmethod
    def from_result(cls, r: FitResult) -> "FitOut":
        return cls(
            score=r.score,
            tier=r.tier,
            delta=r.delta,
            lifestyle=FitLifestyleOut(
                overall=r.lifestyle.overall,
                answered=r.lifestyle.answered,
                total=r.lifestyle.total,
                dims=[
                    FitDimOut(key=d.key, label=d.label, score=d.score,
                              weight=d.weight, detail=d.detail)
                    for d in r.lifestyle.dims
                ],
            ),
            medicines=FitMedicinesOut(
                overall=r.medicines.overall,
                scans_in_window=r.medicines.scans_in_window,
                meds=[
                    FitMedItemOut(name=m.name, identified=m.identified,
                                  score=m.score, note=m.note,
                                  interactions=m.interactions)
                    for m in r.medicines.meds
                ],
            ),
            focus=(
                FitFocusOut(area=r.focus.area, key=r.focus.key,
                            label=r.focus.label, score=r.focus.score,
                            message=r.focus.message)
                if r.focus else None
            ),
        )
