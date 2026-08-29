"""scan_history reshaped as the Phase 5.1 automatic diet log

Revision ID: a1c0ffee0008
Revises: a1c0ffee0007
Create Date: 2026-08-29 00:00:00.000000

The old scan_history (brand / raw_ingredients / flags / nutrients / logged) was
a speculative Phase 2 shape that nothing ever wrote to. Replace it with the
diet-log shape: user_id, product_name, barcode, score, tier, hard_stop,
key_reasons, scanned_at. product_name / barcode / key_reasons are
application-layer encrypted (TEXT holding a Fernet token), like the rest of the
vault.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "a1c0ffee0008"
down_revision: Union[str, None] = "a1c0ffee0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_table("scan_history")  # empty + unused; drops its indexes/FKs with it

    op.create_table(
        "scan_history",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column(
            "seq", sa.BigInteger(), sa.Identity(always=False), nullable=False
        ),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("product_name", sa.Text(), nullable=False),
        sa.Column("barcode", sa.Text(), nullable=True),
        sa.Column("score", sa.Integer(), nullable=False),
        sa.Column("tier", sa.String(length=12), nullable=False),
        sa.Column(
            "hard_stop", sa.Boolean(), server_default=sa.text("false"), nullable=False
        ),
        sa.Column("key_reasons", sa.Text(), nullable=False),
        sa.Column(
            "scanned_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_scan_history_seq", "scan_history", ["seq"])
    op.create_index("ix_scan_history_user_id", "scan_history", ["user_id"])
    op.create_index("ix_scan_history_scanned_at", "scan_history", ["scanned_at"])


def downgrade() -> None:
    op.drop_index("ix_scan_history_scanned_at", table_name="scan_history")
    op.drop_index("ix_scan_history_seq", table_name="scan_history")
    op.drop_index("ix_scan_history_user_id", table_name="scan_history")
    op.drop_table("scan_history")

    op.create_table(
        "scan_history",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("product_name", sa.String(length=200), nullable=False),
        sa.Column("brand", sa.String(length=160), nullable=True),
        sa.Column("barcode", sa.String(length=64), nullable=True),
        sa.Column("raw_ingredients", sa.Text(), nullable=True),
        sa.Column("verdict", sa.String(length=20), nullable=True),
        sa.Column("score", sa.Integer(), nullable=True),
        sa.Column(
            "flags",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'[]'::jsonb"),
            nullable=False,
        ),
        sa.Column(
            "nutrients",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'[]'::jsonb"),
            nullable=False,
        ),
        sa.Column(
            "logged", sa.Boolean(), server_default=sa.text("false"), nullable=False
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_scan_history_barcode", "scan_history", ["barcode"])
    op.create_index("ix_scan_history_user_id", "scan_history", ["user_id"])
