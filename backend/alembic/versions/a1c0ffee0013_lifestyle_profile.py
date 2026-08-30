"""lifestyle profile (inputs to the CareCart Fit score)

Revision ID: a1c0ffee0013
Revises: a1c0ffee0012
Create Date: 2026-08-31 00:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a1c0ffee0013"
down_revision: Union[str, None] = "a1c0ffee0012"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "lifestyle_profiles",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        # Fernet-encrypted JSON blob (app-layer), stored as text
        sa.Column("data", sa.Text(), nullable=True),
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
        sa.UniqueConstraint("user_id"),
    )
    op.create_index(
        "ix_lifestyle_profiles_user_id", "lifestyle_profiles", ["user_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_lifestyle_profiles_user_id", table_name="lifestyle_profiles")
    op.drop_table("lifestyle_profiles")
