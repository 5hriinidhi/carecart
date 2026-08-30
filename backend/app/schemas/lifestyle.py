"""Request/response models for the lifestyle profile (CareCart Fit inputs)."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, model_validator

_SMOKING = {"none", "occasional", "daily"}
_ALCOHOL = {"none", "occasional", "weekly", "daily"}


class LifestyleIn(BaseModel):
    """Full replacement payload. Every field optional — a user may answer none,
    some, or all of the lifestyle questions."""

    model_config = ConfigDict(extra="forbid")

    sleep_hours: float | None = Field(default=None, ge=0, le=24)
    exercise_days: int | None = Field(default=None, ge=0, le=7)
    smoking: str | None = Field(default=None)
    alcohol: str | None = Field(default=None)
    stress: int | None = Field(default=None, ge=1, le=5)

    @model_validator(mode="after")
    def _check_enums(self):
        if self.smoking is not None and self.smoking not in _SMOKING:
            raise ValueError(f"smoking must be one of {sorted(_SMOKING)}")
        if self.alcohol is not None and self.alcohol not in _ALCOHOL:
            raise ValueError(f"alcohol must be one of {sorted(_ALCOHOL)}")
        return self

    def as_data(self) -> dict:
        """Only the keys the caller actually set (so PATCH-style merges work)."""
        return self.model_dump(exclude_none=True)


class LifestylePatch(LifestyleIn):
    """Same shape; the route merges set fields into the stored blob."""


class LifestyleOut(BaseModel):
    sleep_hours: float | None = None
    exercise_days: int | None = None
    smoking: str | None = None
    alcohol: str | None = None
    stress: int | None = None

    @classmethod
    def from_data(cls, data: dict | None) -> "LifestyleOut":
        d = data or {}
        return cls(
            sleep_hours=d.get("sleep_hours"),
            exercise_days=d.get("exercise_days"),
            smoking=d.get("smoking"),
            alcohol=d.get("alcohol"),
            stress=d.get("stress"),
        )
