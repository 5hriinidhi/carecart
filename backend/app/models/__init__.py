"""ORM models. Mirrors the onboarding + scan flow in the CareCart prototype.

Import every model here so Alembic autogenerate sees them.
"""

from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import Date, ForeignKey, Numeric, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin


def _uuid() -> uuid.UUID:
    return uuid.uuid4()


class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    phone_e164: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(120))
    is_active: Mapped[bool] = mapped_column(default=True)

    profiles: Mapped[list[Profile]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class Profile(Base, TimestampMixin):
    """A person being shopped for (self, parent, child) - see the profile switcher."""

    __tablename__ = "profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(120))
    relation: Mapped[str] = mapped_column(
        String(40), default="self"
    )  # self | parent | child | other

    # onboarding step 1-3
    sex: Mapped[str | None] = mapped_column(String(20))  # male | female | undisclosed
    activity_level: Mapped[str | None] = mapped_column(String(20))  # sedentary | moderate | heavy
    weight_kg: Mapped[float | None] = mapped_column(Numeric(5, 2))
    height_cm: Mapped[float | None] = mapped_column(Numeric(5, 2))
    date_of_birth: Mapped[dt.date | None] = mapped_column(Date)

    # onboarding step 4-5 (free-form tag lists)
    diet_preferences: Mapped[list[str]] = mapped_column(ARRAY(String), default=list)
    allergens: Mapped[list[str]] = mapped_column(ARRAY(String), default=list)

    # derived per-serving ceilings (sodium/sugar/potassium/...), filled by the profile builder
    nutrient_ceilings: Mapped[dict] = mapped_column(JSONB, default=dict)

    conditions: Mapped[list[str]] = mapped_column(ARRAY(String), default=list)

    user: Mapped[User] = relationship(back_populates="profiles")
    medications: Mapped[list[Medication]] = relationship(
        back_populates="profile", cascade="all, delete-orphan"
    )
    scans: Mapped[list[ScanHistory]] = relationship(
        back_populates="profile", cascade="all, delete-orphan"
    )


class Medication(Base, TimestampMixin):
    __tablename__ = "medications"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    profile_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("profiles.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(160))
    active_ingredient: Mapped[str | None] = mapped_column(String(160))
    drug_class: Mapped[str | None] = mapped_column(String(120))  # from data_prep/drug_classes.csv
    dose: Mapped[str | None] = mapped_column(String(80))
    schedule: Mapped[str | None] = mapped_column(String(80))
    is_active: Mapped[bool] = mapped_column(default=True)

    profile: Mapped[Profile] = relationship(back_populates="medications")


class ScanHistory(Base, TimestampMixin):
    __tablename__ = "scan_history"
    __table_args__ = (UniqueConstraint("profile_id", "id", name="uq_scan_profile_id"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    profile_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("profiles.id", ondelete="CASCADE"), index=True
    )
    product_name: Mapped[str] = mapped_column(String(200))
    brand: Mapped[str | None] = mapped_column(String(160))
    barcode: Mapped[str | None] = mapped_column(String(64), index=True)
    raw_ingredients: Mapped[str | None] = mapped_column(Text)

    verdict: Mapped[str | None] = mapped_column(String(20))  # avoid | caution | safe
    score: Mapped[int | None]
    flags: Mapped[list[dict]] = mapped_column(JSONB, default=list)
    nutrients: Mapped[list[dict]] = mapped_column(JSONB, default=list)
    logged: Mapped[bool] = mapped_column(default=False)

    profile: Mapped[Profile] = relationship(back_populates="scans")


__all__ = ["User", "Profile", "Medication", "ScanHistory"]
