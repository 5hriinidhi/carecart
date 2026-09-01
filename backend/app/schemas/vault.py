"""Request/response models for the health identity vault (Phase 3.2).

`*Out` models read straight off the ORM rows — encrypted columns are already
decrypted by :class:`app.db.types.EncryptedString` by the time they're
serialised.
"""

from __future__ import annotations

import datetime as dt
import re
import uuid
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

# Server-side length / range limits so a client can't submit a 5000-char
# "condition" or an unbounded body_metrics blob.
_DietTag = Annotated[str, Field(min_length=1, max_length=60)]
_DietList = Annotated[list[_DietTag], Field(max_length=40)]

_CTRL = re.compile(r"[\x00-\x1f\x7f]")


def _clean_text(v: str | None, *, allow_blank: bool = False) -> str | None:
    """Trim, collapse whitespace and strip control chars from a free-text field
    before it reaches an encrypted column. Raises on an all-blank string (unless
    ``allow_blank``) so a client can't store `"   "`."""
    if v is None:
        return None
    cleaned = re.sub(r"\s{2,}", " ", _CTRL.sub("", v).strip())
    if not cleaned:
        if allow_blank:
            return None
        raise ValueError("must not be blank")
    return cleaned


class _Orm(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --------------------------------------------------------------------- account
class MeOut(_Orm):
    display_name: str | None


class MePatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    display_name: str | None = Field(default=None, min_length=1, max_length=60)
    _clean = field_validator("display_name")(_clean_text)


class BodyMetrics(BaseModel):
    """Onboarding step 3. Fixed shape - no arbitrary keys, bounded numbers."""

    model_config = ConfigDict(extra="forbid")
    weight: float | None = Field(default=None, ge=0, le=1000)
    height: float | None = Field(default=None, ge=0, le=300)
    weight_unit: str | None = Field(default=None, max_length=8)
    height_unit: str | None = Field(default=None, max_length=8)


# --------------------------------------------------------------- health profile
def _clean_lower(v: str | None) -> str | None:
    c = _clean_text(v, allow_blank=True)
    return c.lower() if c else c


class HealthProfileIn(BaseModel):
    gender: str | None = Field(default=None, max_length=30)
    activity_level: str | None = Field(default=None, max_length=20)
    body_metrics: BodyMetrics = Field(default_factory=BodyMetrics)
    diet_type: _DietList = Field(default_factory=list)
    _g = field_validator("gender")(_clean_lower)
    _a = field_validator("activity_level")(_clean_lower)


class HealthProfilePatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    gender: str | None = Field(default=None, max_length=30)
    activity_level: str | None = Field(default=None, max_length=20)
    body_metrics: BodyMetrics | None = None
    diet_type: _DietList | None = None


class HealthProfileOut(_Orm):
    id: uuid.UUID
    gender: str | None
    activity_level: str | None
    body_metrics: dict
    diet_type: list[str]
    created_at: dt.datetime
    updated_at: dt.datetime


# --------------------------------------------------------------------- condition
class ConditionIn(BaseModel):
    condition_name: str = Field(min_length=1, max_length=200)
    _clean = field_validator("condition_name")(_clean_text)


class ConditionPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    condition_name: str | None = Field(default=None, min_length=1, max_length=200)
    _clean = field_validator("condition_name")(_clean_text)


class ConditionOut(_Orm):
    id: uuid.UUID
    condition_name: str
    created_at: dt.datetime
    updated_at: dt.datetime


# ----------------------------------------------------------------------- allergy
class AllergyIn(BaseModel):
    allergen_name: str = Field(min_length=1, max_length=120)
    _clean = field_validator("allergen_name")(_clean_text)


class AllergyPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    allergen_name: str | None = Field(default=None, min_length=1, max_length=120)
    _clean = field_validator("allergen_name")(_clean_text)


class AllergyOut(_Orm):
    id: uuid.UUID
    allergen_name: str
    created_at: dt.datetime
    updated_at: dt.datetime


# -------------------------------------------------------------------- medication
def _clean_optional(v: str | None) -> str | None:
    return _clean_text(v, allow_blank=True)


def _check_active_range(m):
    if m.active_from and m.active_to and m.active_to < m.active_from:
        raise ValueError("active_to must not be before active_from")
    return m


class MedicationIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    dosage: str | None = Field(default=None, max_length=200)
    active_from: dt.date | None = None
    active_to: dt.date | None = None
    _clean_name = field_validator("name")(_clean_text)
    _clean_dose = field_validator("dosage")(_clean_optional)
    _range = model_validator(mode="after")(_check_active_range)


class MedicationPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = Field(default=None, min_length=1, max_length=200)
    dosage: str | None = Field(default=None, max_length=200)
    active_from: dt.date | None = None
    active_to: dt.date | None = None
    _clean_name = field_validator("name")(_clean_text)
    _clean_dose = field_validator("dosage")(_clean_optional)
    _range = model_validator(mode="after")(_check_active_range)


class MedicationOut(_Orm):
    id: uuid.UUID
    name: str
    dosage: str | None
    active_from: dt.date | None
    active_to: dt.date | None
    created_at: dt.datetime
    updated_at: dt.datetime


class MedicationMappingItem(BaseModel):
    """What a stored medication resolves to: its drug class(es) and the food
    risk-compounds those classes are known to interact with. Read-only, derived
    from the same static tables the verdict engine uses — no user data beyond
    the medication name itself."""

    name: str
    identified: bool
    drug_classes: list[str] = []
    interactions: list[str] = []  # risk-compound display names


class MedicationScanOut(BaseModel):
    """The result of OCR-ing a label. A *guess* only — the client shows it, the
    user confirms/edits, then saves it via ``POST /me/medications``. Nothing is
    persisted by the scan itself."""

    name_candidate: str | None = Field(
        default=None, description="Best guess at the drug name, or null if none was found."
    )
    name_confidence: float = Field(
        ge=0.0, le=1.0, description="0-1 confidence in name_candidate."
    )
    dosage_candidate: str | None = Field(
        default=None, description='e.g. "40 mg", extracted from the label text.'
    )
    raw_text: str = Field(description="Sanitised OCR text (control chars stripped, length capped).")
    raw_text_truncated: bool = Field(
        default=False, description="True if raw_text was cut to the length cap."
    )
    confirmation_required: bool = Field(
        default=True,
        description="Always true — this result is not saved until the user confirms it.",
    )
