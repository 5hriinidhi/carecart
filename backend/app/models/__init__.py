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

from sqlalchemy import (
    BigInteger,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Identity,
    Integer,
    String,
    Text,
    func,
    text,
)
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
    # IANA name (e.g. "Asia/Kolkata"), learned from the client on GET
    # /analytics/trends. NULL -> analytics bucket in UTC.
    timezone: Mapped[str | None] = mapped_column(String(64))

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


class ScanHistory(Base):
    """Automatic diet log — one row per completed ``POST /scan/verdict``
    (Phase 5.1). Written server-side on every verdict; the client never has to
    call a separate "log this" endpoint. Cascade-deletes with the user.

    ``score`` / ``tier`` / ``scanned_at`` stay plaintext — they are structural
    and Phase 5.2 trends aggregate on them (``AVG(score) GROUP BY week``). The
    identifying bits — what the user actually scanned — are Fernet-encrypted at
    rest like the rest of the vault: ``product_name``, ``barcode``,
    ``key_reasons``. Encrypted columns are only ever filtered by ``user_id``.
    """

    __tablename__ = "scan_history"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    # monotonic insertion order — the authoritative "most recent first" key, so
    # pagination is stable even when two scans share a scanned_at timestamp.
    seq: Mapped[int] = mapped_column(BigInteger, Identity(), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    product_name: Mapped[str] = mapped_column(EncryptedString)          # encrypted at rest
    barcode: Mapped[str | None] = mapped_column(EncryptedString)        # encrypted at rest
    score: Mapped[int] = mapped_column(Integer)
    tier: Mapped[str] = mapped_column(String(12))                      # safe | caution | avoid
    hard_stop: Mapped[bool] = mapped_column(default=False, server_default=text("false"))
    # top few reasons behind the verdict: [{"kind","severity","title"}, ...]
    key_reasons: Mapped[list[dict]] = mapped_column(EncryptedJSON, default=list)
    # wall-clock time the verdict was produced (set by the route, not the DB txn)
    scanned_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )


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


# ============================================ ingredient risk resolution (4.3) ==
# These five tables are the pre-built STATIC reference data the scan path
# resolves against. They hold no user data and are never written to on the scan
# path except `unresolved_ingredients` (an append/counter queue). Populated from
# dataset/data_prep/*.csv by `scripts/load_risk_tables.py`. No LLM is ever
# called at runtime - unknown ingredients are queued here for the offline batch
# job (`scripts/classify_unresolved.py`).


class RiskCompound(Base):
    """The 26 canonical food-chemistry categories relevant to drug interactions
    (from ``risk_compounds.csv``). Referenced by every table below."""

    __tablename__ = "risk_compounds"

    risk_compound: Mapped[str] = mapped_column(String(48), primary_key=True)
    display_name: Mapped[str] = mapped_column(String(120))
    category: Mapped[str | None] = mapped_column(String(32))
    description: Mapped[str | None] = mapped_column(Text)
    typical_food_sources: Mapped[str | None] = mapped_column(Text)
    why_it_matters_for_drugs: Mapped[str | None] = mapped_column(Text)


class IngredientRiskAlias(Base):
    """``alias -> risk_compound`` keyword dictionary, merged from the hand-authored
    ``ingredient_aliases.csv`` (``source='keyword'``) and the reviewed LLM-fallback
    ``llm_ingredient_tags.csv`` (``source='llm'``). A row with ``risk_compound`` NULL
    is a token explicitly reviewed as carrying no risk compound (so it resolves as
    known-benign, not "unverified"). The offline batch job appends ``source='batch'``
    rows after human review."""

    __tablename__ = "ingredient_risk_aliases"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    alias: Mapped[str] = mapped_column(String(160), index=True)
    risk_compound: Mapped[str | None] = mapped_column(
        ForeignKey("risk_compounds.risk_compound", ondelete="RESTRICT")
    )
    match_type: Mapped[str] = mapped_column(String(12))  # substring | word | exact
    confidence: Mapped[float | None] = mapped_column(Float)
    source: Mapped[str] = mapped_column(String(16))  # keyword | llm | batch
    notes: Mapped[str | None] = mapped_column(Text)
    rationale: Mapped[str | None] = mapped_column(Text)


class RiskNutrientThreshold(Base):
    """Numeric-threshold counterpart to the alias table: a per-100 g nutrient
    level at or above which a ``risk_compound`` applies to the whole product
    (from ``risk_nutrient_thresholds.csv``). Keys match the normalised nutriment
    keys produced by the Open Food Facts lookup (Phase 4.1)."""

    __tablename__ = "risk_nutrient_thresholds"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    risk_compound: Mapped[str] = mapped_column(
        ForeignKey("risk_compounds.risk_compound", ondelete="RESTRICT")
    )
    nutrient_key: Mapped[str] = mapped_column(String(48), index=True)
    basis: Mapped[str] = mapped_column(String(16), default="per_100g")
    min_value: Mapped[float] = mapped_column(Float)
    confidence: Mapped[float] = mapped_column(Float)
    method: Mapped[str] = mapped_column(String(16), default="threshold")
    source: Mapped[str | None] = mapped_column(String(32))
    rationale: Mapped[str | None] = mapped_column(Text)


class FoodRiskTag(Base):
    """Per-food precomputed ``(food_id, risk_compound)`` tags from the one-time
    data-prep job (``food_risk_tags.csv``). Not on the resolve path (barcodes
    don't map to dataset food ids); loaded for Phase 4.4 to reuse when a scan
    matches a known dataset item, and to spot-check the alias tables against."""

    __tablename__ = "food_risk_tags"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    food_id: Mapped[str] = mapped_column(String(16), index=True)
    risk_compound: Mapped[str] = mapped_column(
        ForeignKey("risk_compounds.risk_compound", ondelete="RESTRICT")
    )
    confidence: Mapped[float | None] = mapped_column(Float)
    method: Mapped[str | None] = mapped_column(String(24))


class UnresolvedIngredient(Base):
    """Queue of ingredient strings the static tables could not resolve.

    One row per distinct (normalised) ingredient text - repeat sightings bump
    ``times_seen`` and ``last_seen_at`` instead of inserting a duplicate. Drained
    by the offline batch job (``scripts/classify_unresolved.py``), which
    classifies the batch and, after human review, merges accepted results back
    into the alias CSVs for the next deploy. No LLM is called to fill this on the
    scan path."""

    __tablename__ = "unresolved_ingredients"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    ingredient_text: Mapped[str] = mapped_column(String(200))
    # dedup key: lowercased + cleaned form of ingredient_text
    normalized_text: Mapped[str] = mapped_column(String(200), unique=True, index=True)
    sample_product: Mapped[str | None] = mapped_column(String(200))
    times_seen: Mapped[int] = mapped_column(Integer, default=1, server_default=text("1"))
    status: Mapped[str] = mapped_column(
        String(12), default="pending", server_default=text("'pending'")
    )  # pending | classified | merged | rejected
    first_seen_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    last_seen_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


# ================================ food-drug interaction & severity scoring (4.4) ==
# More pre-built STATIC reference data - the rules `POST /scan/verdict` scores
# against. No user data; loaded from dataset/data_prep/*.csv by
# `scripts/load_risk_tables.py`. Every interaction row is a clinician-review
# DRAFT (see interaction_rules.csv) - the endpoint returns "keep consistent" /
# "caution" style verdicts, not medical advice.


class InteractionRule(Base):
    """One ``(drug_class x risk_compound)`` food-drug interaction pattern from
    ``interaction_rules.csv`` (e.g. vitamin-K antagonist x vitamin_k,
    mood-stabiliser x sodium). ``severity`` drives the score deduction."""

    __tablename__ = "interaction_rules"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    drug_class: Mapped[str] = mapped_column(String(80), index=True)
    risk_compound: Mapped[str] = mapped_column(
        ForeignKey("risk_compounds.risk_compound", ondelete="RESTRICT"), index=True
    )
    severity: Mapped[str] = mapped_column(String(12))  # HIGH | MODERATE | LOW
    mechanism: Mapped[str | None] = mapped_column(Text)
    dietary_guidance: Mapped[str | None] = mapped_column(Text)
    evidence_strength: Mapped[str | None] = mapped_column(String(24))
    example_drugs: Mapped[str | None] = mapped_column(Text)


class DrugClassLookup(Base):
    """``active_ingredient -> drug_class`` (from ``drug_class_lookup.csv`` +
    ``llm_drug_classes.csv``). Used to map a stored medication name onto a
    ``drug_class`` so :class:`InteractionRule` rows can fire."""

    __tablename__ = "drug_class_lookup"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    active_ingredient: Mapped[str] = mapped_column(String(120), index=True)
    drug_class: Mapped[str] = mapped_column(String(80))
    source: Mapped[str] = mapped_column(String(16))  # keyword | llm
    confidence: Mapped[float | None] = mapped_column(Float)


class DrugClassStemRule(Base):
    """Ordered suffix/prefix stem rules (``-pril`` -> ACE inhibitor,
    ``cef-`` -> Cephalosporin) from ``drug_class_stem_rules.csv`` - the fallback
    when an exact ``drug_class_lookup`` match fails."""

    __tablename__ = "drug_class_stem_rules"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    ordinal: Mapped[int] = mapped_column(Integer)
    pattern: Mapped[str] = mapped_column(String(40))
    position: Mapped[str] = mapped_column(String(8))  # prefix | suffix
    drug_class: Mapped[str] = mapped_column(String(80))


class ConditionDietRule(Base):
    """Per-condition dietary rule from ``condition_diet_rules.csv``. Two kinds:
    ``nutrient_ceiling`` (a per-100 g ceiling for a nutriment key) and
    ``risk_compound`` (a compound this condition should avoid). ``severity``
    drives the deduction."""

    __tablename__ = "condition_diet_rules"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    condition: Mapped[str] = mapped_column(String(80), index=True)
    kind: Mapped[str] = mapped_column(String(20))  # nutrient_ceiling | risk_compound
    nutrient_key: Mapped[str | None] = mapped_column(String(48))
    ceiling_per_100g: Mapped[float | None] = mapped_column(Float)
    risk_compound: Mapped[str | None] = mapped_column(
        ForeignKey("risk_compounds.risk_compound", ondelete="RESTRICT")
    )
    severity: Mapped[str] = mapped_column(String(12))  # HIGH | MODERATE | LOW
    guidance: Mapped[str | None] = mapped_column(Text)


class AllergenAlias(Base):
    """``allergy free-text -> allergen risk_compound`` (from
    ``allergen_aliases.csv``). A match between a stored allergy and any ingredient
    carrying that compound is a HARD STOP - a full "avoid", not a deduction."""

    __tablename__ = "allergen_aliases"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    alias: Mapped[str] = mapped_column(String(80), index=True)
    risk_compound: Mapped[str] = mapped_column(
        ForeignKey("risk_compounds.risk_compound", ondelete="RESTRICT")
    )
    notes: Mapped[str | None] = mapped_column(Text)


class DrugNameAlias(Base):
    """``brand name -> generic active ingredient`` (from ``drug_name_aliases.csv``).

    A stored medication is usually a brand ("Ecosprin", "Telma"), but
    ``interaction_rules`` / ``drug_class_lookup`` key off the generic
    ("aspirin", "telmisartan"). The verdict resolver maps through this table
    before the class lookup so brand/generic mismatches don't silently skip an
    interaction check."""

    __tablename__ = "drug_name_aliases"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    alias: Mapped[str] = mapped_column(String(80), index=True)
    generic: Mapped[str] = mapped_column(String(120))
    notes: Mapped[str | None] = mapped_column(Text)


class DrugCatalog(Base):
    """Searchable catalogue of Indian medicine brand names (from
    ``dataset/data_prep/drug_classes.csv``, deduped to one row per
    ``product_name``). Backs ``GET /drugs/search`` so a user picks their
    medication from a list instead of typing a free-text name (or OCR-ing a
    strip). Static reference data — no user data, loaded by
    ``scripts.load_drug_catalog``."""

    __tablename__ = "drug_catalog"

    id: Mapped[int] = mapped_column(Integer, Identity(), primary_key=True)
    product_name: Mapped[str] = mapped_column(String(300), unique=True, index=True)
    salt_composition: Mapped[str | None] = mapped_column(String(500))
    # comma-joined distinct values across the source rows for this product_name
    active_ingredients: Mapped[str | None] = mapped_column(String(500))
    drug_classes: Mapped[str | None] = mapped_column(String(300))


class Nudge(Base):
    """A behavioural nudge (Phase 5.3): generated server-side when a user racks
    up 3+ non-safe scans for the same recurring ``factor`` (risk_compound) in a
    rolling 14-day window. ``message`` is a specific, actionable suggestion.

    ``message`` is Fernet-encrypted at rest (health behaviour); ``factor`` stays
    plaintext — it's the de-dup key (one nudge per user per factor per window)
    and Phase 5.x may group on it.
    """

    __tablename__ = "nudges"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    seq: Mapped[int] = mapped_column(BigInteger, Identity(), index=True)  # poll cursor
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    factor: Mapped[str] = mapped_column(String(48), index=True)
    message: Mapped[str] = mapped_column(EncryptedString)   # encrypted at rest
    hit_count: Mapped[int] = mapped_column(Integer)
    window_days: Mapped[int] = mapped_column(Integer, default=14)
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )
    dismissed_at: Mapped[dt.datetime | None] = mapped_column(DateTime(timezone=True))


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
    "RiskCompound",
    "IngredientRiskAlias",
    "RiskNutrientThreshold",
    "FoodRiskTag",
    "UnresolvedIngredient",
    "InteractionRule",
    "DrugClassLookup",
    "DrugClassStemRule",
    "DrugCatalog",
    "ConditionDietRule",
    "AllergenAlias",
    "DrugNameAlias",
    "Nudge",
    "AuditLog",
]
