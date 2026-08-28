"""encrypt all PHI columns + add audit_log

Revision ID: a1c0ffee0003
Revises: a1c0ffee0002
Create Date: 2026-08-28 00:00:00.000000

Widens the encrypted-at-rest boundary to cover every PHI column in the vault:
allergies.allergen_name and the health_profiles demographic/body fields now hold
Fernet ciphertext (TEXT) instead of plaintext. Adds an append-only audit_log
(who / verb / resource / when - no health-data content).

NOTE: TRUNCATEs health_profiles and allergies - plaintext values can't be cast
to ciphertext, and there are no real accounts yet.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "a1c0ffee0003"
down_revision: Union[str, None] = "a1c0ffee0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("TRUNCATE TABLE health_profiles, allergies")

    op.alter_column(
        "allergies", "allergen_name", type_=sa.Text(), existing_nullable=False
    )

    op.alter_column("health_profiles", "gender", type_=sa.Text(), existing_nullable=True)
    op.alter_column(
        "health_profiles", "activity_level", type_=sa.Text(), existing_nullable=True
    )
    op.alter_column(
        "health_profiles",
        "body_metrics",
        type_=sa.Text(),
        server_default=None,
        existing_nullable=False,
        postgresql_using="body_metrics::text",
    )
    op.alter_column(
        "health_profiles",
        "diet_type",
        type_=sa.Text(),
        server_default=None,
        existing_nullable=False,
        postgresql_using="diet_type::text",
    )

    op.create_table(
        "audit_log",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("action", sa.String(length=12), nullable=False),
        sa.Column("resource", sa.String(length=40), nullable=False),
        sa.Column("resource_id", sa.UUID(), nullable=True),
        sa.Column("status_code", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_audit_log_user_id", "audit_log", ["user_id"])
    op.create_index("ix_audit_log_created_at", "audit_log", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_audit_log_created_at", table_name="audit_log")
    op.drop_index("ix_audit_log_user_id", table_name="audit_log")
    op.drop_table("audit_log")

    op.execute("TRUNCATE TABLE health_profiles, allergies")

    op.alter_column(
        "allergies",
        "allergen_name",
        type_=sa.String(length=120),
        existing_nullable=False,
        postgresql_using="allergen_name::varchar(120)",
    )
    op.alter_column(
        "health_profiles",
        "gender",
        type_=sa.String(length=30),
        existing_nullable=True,
        postgresql_using="gender::varchar(30)",
    )
    op.alter_column(
        "health_profiles",
        "activity_level",
        type_=sa.String(length=20),
        existing_nullable=True,
        postgresql_using="activity_level::varchar(20)",
    )
    op.alter_column(
        "health_profiles",
        "body_metrics",
        type_=postgresql.JSONB(astext_type=sa.Text()),
        server_default=sa.text("'{}'::jsonb"),
        existing_nullable=False,
        postgresql_using="body_metrics::jsonb",
    )
    op.alter_column(
        "health_profiles",
        "diet_type",
        type_=postgresql.ARRAY(sa.String()),
        server_default=sa.text("'{}'::varchar[]"),
        existing_nullable=False,
        postgresql_using="string_to_array(diet_type, ',')",
    )
