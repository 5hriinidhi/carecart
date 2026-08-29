"""brand -> generic drug name aliases (Phase 4 edge cases)

Revision ID: a1c0ffee0007
Revises: a1c0ffee0006
Create Date: 2026-08-29 00:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a1c0ffee0007"
down_revision: Union[str, None] = "a1c0ffee0006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "drug_name_aliases",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("alias", sa.String(length=80), nullable=False),
        sa.Column("generic", sa.String(length=120), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_drug_name_aliases_alias", "drug_name_aliases", ["alias"])


def downgrade() -> None:
    op.drop_index("ix_drug_name_aliases_alias", table_name="drug_name_aliases")
    op.drop_table("drug_name_aliases")
