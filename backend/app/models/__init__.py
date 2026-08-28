"""ORM models — the Health Identity Vault (Phase 3.2) + auth (3.1).

Everything is keyed to ``users.id``. A user only ever sees their own rows; the
API layer enforces that on every query (see ``app/api/deps.py`` +
``app/api/v1/routes/vault``). Every PHI column in the vault - conditions,
allergies, medications, and the health-profile demographic/body fields - is
transparently Fernet-encrypted at rest (:mod:`app.db.types`). Only structural
columns (ids, user_id, timestamps) are plaintext.

Import every model here so Alembic autogenerate sees them.
"""

from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import Date, DateTime, ForeignKey, Integer, String, Text, func, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin
from app.db.types import EncryptedJSON, EncryptedString


def _uuid() -> uuid.UUID:
    return uuid.uuid4()


# ============================================================ identity / auth ==
class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    # keyed HMAC of the E.164 number — the plaintext phone is never stored
    phone_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(120))
    is_active: Mapped[bool] = mapped_column(default=True)

    health_profile: Mapped[HealthProfile | None] = relationship(
        back_populates="user", cascade="all, delete-orphan", uselist=False
    )
    conditions: Mapped[list[Condition]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    allergies: Mapped[list[Allergy]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    medications: Mapped[list[Medication]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class OtpChallenge(Base, TimestampMixin):
    """A pending phone-verification code.

    Only the bcrypt hash of the code is stored — the raw 6 digits exist for one
    request/response cycle and are never persisted or logged. Rows are retained
    (not deleted) for the length of the rate-limit window so ``request-otp``
    throttling can count them; ``purge_stale`` clears anything older than a day.
    ``phone_e164`` here is transient (row expires in minutes, purged in a day)
    and is needed to group rate-limit counts — this is not the identity store.
    """

    __tablename__ = "otp_challenges"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    phone_e164: Mapped[str] = mapped_column(String(20), index=True)
    code_hash: Mapped[str] = mapped_column(String(120))  # bcrypt; never the raw code
    expires_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), index=True)
    consumed_at: Mapped[dt.datetime | None] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(default=0, server_default=text("0"))


class RefreshToken(Base, TimestampMixin):
    """A long-lived, revocable session credential.

    The client holds an opaque random string; we store only its SHA-256 hash.
    Rotated on every ``POST /auth/refresh`` (old row is revoked, new one issued).
    """

    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)  # sha256 hex
    expires_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[dt.datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped[User] = relationship()


# =================================================== health identity vault ==
class HealthProfile(Base, TimestampMixin):
    """Onboarding steps 1–4: gender, activity level, body metrics, diet type.
    One row per user (allergies and medications are their own tables)."""

    __tablename__ = "health_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )

    # all PHI -> encrypted at rest
    gender: Mapped[str | None] = mapped_column(EncryptedString)
    activity_level: Mapped[str | None] = mapped_column(EncryptedString)
    body_metrics: Mapped[dict] = mapped_column(EncryptedJSON, default=dict)
    diet_type: Mapped[list[str]] = mapped_column(EncryptedJSON, default=list)

    user: Mapped[User] = relationship(back_populates="health_profile")


class Condition(Base, TimestampMixin):
    __tablename__ = "conditions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    condition_name: Mapped[str] = mapped_column(EncryptedString)  # encrypted at rest

    user: Mapped[User] = relationship(back_populates="conditions")


class Allergy(Base, TimestampMixin):
    __tablename__ = "allergies"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    allergen_name: Mapped[str] = mapped_column(EncryptedString)  # encrypted at rest

    user: Mapped[User] = relationship(back_populates="allergies")


class Medication(Base, TimestampMixin):
    __tablename__ = "medications"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(EncryptedString)                 # encrypted at rest
    dosage: Mapped[str | None] = mapped_column(EncryptedString)        # encrypted at rest
    active_from: Mapped[dt.date | None] = mapped_column(Date)
    active_to: Mapped[dt.date | None] = mapped_column(Date)

    user: Mapped[User] = relationship(back_populates="medications")


class ScanHistory(Base, TimestampMixin):
    """Kept for later phases; repointed from profile_id -> user_id in 3.2."""

    __tablename__ = "scan_history"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    product_name: Mapped[str] = mapped_column(String(200))
    brand: Mapped[str | None] = mapped_column(String(160))
    barcode: Mapped[str | None] = mapped_column(String(64), index=True)
    raw_ingredients: Mapped[str | None] = mapped_column(Text)

    verdict: Mapped[str | None] = mapped_column(String(20))  # avoid | caution | safe
    score: Mapped[int | None]
    flags: Mapped[list[dict]] = mapped_column(JSONB, default=list, server_default=text("'[]'"))
    nutrients: Mapped[list[dict]] = mapped_column(JSONB, default=list, server_default=text("'[]'"))
    logged: Mapped[bool] = mapped_column(default=False)


class Product(Base, TimestampMixin):
    """Open Food Facts lookup cache, keyed by barcode.

    Public product data (not user-linked, not PHI) - stored plaintext. Both hits
    and misses are cached: ``off_status='not_found'`` rows stop us from hammering
    OFF for a barcode it doesn't have. ``refreshed_at`` drives the >= 24h TTL.
    """

    __tablename__ = "products"

    barcode: Mapped[str] = mapped_column(String(14), primary_key=True)
    off_status: Mapped[str] = mapped_column(String(10))  # found | not_found

    name: Mapped[str | None] = mapped_column(String(300))
    brand: Mapped[str | None] = mapped_column(String(200))
    ingredients_text: Mapped[str | None] = mapped_column(Text)
    ingredients: Mapped[list[str]] = mapped_column(JSONB, default=list, server_default=text("'[]'"))
    nutriments: Mapped[dict] = mapped_column(JSONB, default=dict, server_default=text("'{}'"))
    serving_size: Mapped[str | None] = mapped_column(String(80))
    image_url: Mapped[str | None] = mapped_column(String(500))

    source: Mapped[str] = mapped_column(
        String(40), default="openfoodfacts", server_default=text("'openfoodfacts'")
    )
    raw: Mapped[dict | None] = mapped_column(JSONB)
    refreshed_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), index=True)


class AuditLog(Base):
    """Append-only record of WHO touched WHICH health resource and WHEN.

    Deliberately holds no health data content - only the acting user, a verb,
    the resource kind, the row id (when applicable) and the response status.
    Rows cascade-delete with the user so account erasure stays complete.
    """

    __tablename__ = "audit_log"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    action: Mapped[str] = mapped_column(String(12))     # read | write | delete
    resource: Mapped[str] = mapped_column(String(40))   # conditions | medications | ...
    resource_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    status_code: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )


__all__ = [
    "User",
    "OtpChallenge",
    "RefreshToken",
    "HealthProfile",
    "Condition",
    "Allergy",
    "Medication",
    "ScanHistory",
    "Product",
    "AuditLog",
]
