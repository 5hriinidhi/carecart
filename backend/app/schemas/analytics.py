"""Analytics / trends payloads (Phase 5.2)."""

from __future__ import annotations

import datetime as dt

from pydantic import BaseModel, Field


class TrendBucket(BaseModel):
    period_start: dt.date = Field(description="Local date of the bucket start (Mon / 1st).")
    label: str
    scans: int
    avg_score: float
    median_score: float = Field(
        description="Robust to a single outlier; compare with avg_score to spot skew."
    )
    min_score: int
    max_score: int
    safe: int
    caution: int
    avoid: int
    diet_health_score: int = Field(
        description="Rolling Diet Health Score as of the last scan in this bucket."
    )


class TrendsOut(BaseModel):
    timezone: str = Field(description="The zone used to bucket (IANA name, or 'UTC').")
    total_scans: int
    diet_health_score: int = Field(
        ge=0, le=100, description="Current rolling Diet Health Score (EMA of scan scores)."
    )
    diet_health_score_delta_7d: int = Field(
        description="Change in the score vs ~7 days ago (signed)."
    )
    trend: str = Field(description="improving | declining | steady")
    weekly: list[TrendBucket] = Field(default_factory=list)
    monthly: list[TrendBucket] = Field(default_factory=list)
