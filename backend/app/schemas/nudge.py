"""Behavioural nudge payloads (Phase 5.3)."""

from __future__ import annotations

import datetime as dt

from pydantic import BaseModel, ConfigDict, Field, field_validator


class NudgeOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    seq: int
    factor: str
    message: str = Field(description="A specific, actionable suggestion.")
    hit_count: int
    window_days: int
    created_at: dt.datetime
    dismissed_at: dt.datetime | None = None

    @field_validator("id", mode="before")
    @classmethod
    def _stringify_id(cls, v: object) -> str:
        return str(v)


class NudgesPage(BaseModel):
    items: list[NudgeOut]
    latest_seq: int = Field(
        description="Highest nudge seq for this user — pass as ?since= to poll incrementally."
    )
