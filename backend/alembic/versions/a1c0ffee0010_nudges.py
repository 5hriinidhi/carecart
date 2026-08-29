"""nudges — behavioural nudge records (Phase 5.3)

Revision ID: a1c0ffee0010
Revises: a1c0ffee0009
Create Date: 2026-08-30 00:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a1c0ffee0010"
down_revision: Union[str, None] = "a1c0ffee0009"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "nudges",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("seq", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("factor", sa.String(length=48), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("hit_count", sa.Integer(), nullable=False),
        sa.Column("window_days", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("dismissed_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_nudges_seq", "nudges", ["seq"])
    op.create_index("ix_nudges_user_id", "nudges", ["user_id"])
    op.create_index("ix_nudges_factor", "nudges", ["factor"])
    op.create_index("ix_nudges_created_at", "nudges", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_nudges_created_at", table_name="nudges")
    op.drop_index("ix_nudges_factor", table_name="nudges")
    op.drop_index("ix_nudges_user_id", table_name="nudges")
    op.drop_index("ix_nudges_seq", table_name="nudges")
    op.drop_table("nudges")
