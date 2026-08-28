"""health identity vault: phone_hash + health_profiles / conditions / allergies / medications

Revision ID: a1c0ffee0002
Revises: a1c0ffee0001
Create Date: 2026-08-28 00:00:00.000000

Reshapes the vault around users.id and swaps the plaintext users.phone_e164 for
a keyed hash. The old `profiles`-scoped tables are replaced by user-scoped ones.

NOTE: this migration TRUNCATEs `users` (cascading to refresh_tokens / profiles /
medications / scan_history). That is acceptable pre-launch — there are no real
accounts yet and phone numbers cannot be reconstructed from the new hash.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "a1c0ffee0002"
down_revision: Union[str, None] = "a1c0ffee0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_TS = (
    sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
)


def upgrade() -> None:
    op.execute("TRUNCATE TABLE users CASCADE")

    # index that a1c0ffee0001 missed (model has index=True); useful for a
    # future "delete expired refresh tokens" sweep.
    op.create_index(
        "ix_refresh_tokens_expires_at", "refresh_tokens", ["expires_at"], unique=False
    )

    # --- drop the old profile-scoped tables ---------------------------------
    op.drop_index("ix_medications_profile_id", table_name="medications")
    op.drop_table("medications")

    op.drop_constraint("uq_scan_profile_id", "scan_history", type_="unique")
    op.drop_index("ix_scan_history_profile_id", table_name="scan_history")
    op.drop_constraint("scan_history_profile_id_fkey", "scan_history", type_="foreignkey")
    op.alter_column("scan_history", "profile_id", new_column_name="user_id")
    op.create_foreign_key(
        "scan_history_user_id_fkey", "scan_history", "users", ["user_id"], ["id"], ondelete="CASCADE"
    )
    op.create_index("ix_scan_history_user_id", "scan_history", ["user_id"])

    op.drop_index("ix_profiles_user_id", table_name="profiles")
    op.drop_table("profiles")

    # --- users: plaintext phone -> keyed hash ------------------------------
    op.drop_index("ix_users_phone_e164", table_name="users")
    op.drop_column("users", "phone_e164")
    op.add_column("users", sa.Column("phone_hash", sa.String(length=64), nullable=False))
    op.create_index("ix_users_phone_hash", "users", ["phone_hash"], unique=True)

    # --- new user-scoped vault tables -------------------------------------
    op.create_table(
        "health_profiles",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("gender", sa.String(length=30), nullable=True),
        sa.Column("activity_level", sa.String(length=20), nullable=True),
        sa.Column(
            "body_metrics",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.Column(
            "diet_type",
            postgresql.ARRAY(sa.String()),
            server_default=sa.text("'{}'::varchar[]"),
            nullable=False,
        ),
        *_TS,
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_health_profiles_user_id", "health_profiles", ["user_id"], unique=True)

    op.create_table(
        "conditions",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("condition_name", sa.Text(), nullable=False),  # Fernet token (encrypted at rest)
        *_TS,
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_conditions_user_id", "conditions", ["user_id"])

    op.create_table(
        "allergies",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("allergen_name", sa.String(length=120), nullable=False),
        *_TS,
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_allergies_user_id", "allergies", ["user_id"])

    op.create_table(
        "medications",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),  # Fernet token (encrypted at rest)
        sa.Column("dosage", sa.Text(), nullable=True),  # Fernet token (encrypted at rest)
        sa.Column("active_from", sa.Date(), nullable=True),
        sa.Column("active_to", sa.Date(), nullable=True),
        *_TS,
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_medications_user_id", "medications", ["user_id"])


def downgrade() -> None:
    op.execute("TRUNCATE TABLE users CASCADE")

    op.drop_index("ix_refresh_tokens_expires_at", table_name="refresh_tokens")

    op.drop_index("ix_medications_user_id", table_name="medications")
    op.drop_table("medications")
    op.drop_index("ix_allergies_user_id", table_name="allergies")
    op.drop_table("allergies")
    op.drop_index("ix_conditions_user_id", table_name="conditions")
    op.drop_table("conditions")
    op.drop_index("ix_health_profiles_user_id", table_name="health_profiles")
    op.drop_table("health_profiles")

    op.drop_index("ix_users_phone_hash", table_name="users")
    op.drop_column("users", "phone_hash")
    op.add_column("users", sa.Column("phone_e164", sa.String(length=20), nullable=False))
    op.create_index("ix_users_phone_e164", "users", ["phone_e164"], unique=True)

    op.create_table(
        "profiles",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("relation", sa.String(length=40), nullable=False),
        sa.Column("sex", sa.String(length=20), nullable=True),
        sa.Column("activity_level", sa.String(length=20), nullable=True),
        sa.Column("weight_kg", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("height_cm", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("date_of_birth", sa.Date(), nullable=True),
        sa.Column("diet_preferences", postgresql.ARRAY(sa.String()), nullable=False),
        sa.Column("allergens", postgresql.ARRAY(sa.String()), nullable=False),
        sa.Column("nutrient_ceilings", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("conditions", postgresql.ARRAY(sa.String()), nullable=False),
        *_TS,
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_profiles_user_id", "profiles", ["user_id"])

    op.drop_index("ix_scan_history_user_id", table_name="scan_history")
    op.drop_constraint("scan_history_user_id_fkey", "scan_history", type_="foreignkey")
    op.alter_column("scan_history", "user_id", new_column_name="profile_id")
    op.create_foreign_key(
        "scan_history_profile_id_fkey",
        "scan_history",
        "profiles",
        ["profile_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_index("ix_scan_history_profile_id", "scan_history", ["profile_id"])
    op.create_unique_constraint("uq_scan_profile_id", "scan_history", ["profile_id", "id"])

    op.create_table(
        "medications",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("profile_id", sa.UUID(), nullable=False),
        sa.Column("name", sa.String(length=160), nullable=False),
        sa.Column("active_ingredient", sa.String(length=160), nullable=True),
        sa.Column("drug_class", sa.String(length=120), nullable=True),
        sa.Column("dose", sa.String(length=80), nullable=True),
        sa.Column("schedule", sa.String(length=80), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        *_TS,
        sa.ForeignKeyConstraint(["profile_id"], ["profiles.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_medications_profile_id", "medications", ["profile_id"])
