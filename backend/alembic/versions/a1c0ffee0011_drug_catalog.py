"""drug catalog (searchable Indian medicine brand names)

Revision ID: a1c0ffee0011
Revises: a1c0ffee0010
Create Date: 2026-08-30 00:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a1c0ffee0011"
down_revision: Union[str, None] = "a1c0ffee0010"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "drug_catalog",
        sa.Column("id", sa.Integer(), sa.Identity(), nullable=False),
        sa.Column("product_name", sa.String(length=300), nullable=False),
        sa.Column("salt_composition", sa.String(length=500), nullable=True),
        sa.Column("active_ingredients", sa.String(length=500), nullable=True),
        sa.Column("drug_classes", sa.String(length=300), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("product_name"),
    )
    # case-insensitive prefix search: ... WHERE lower(product_name) LIKE 'q%'
    op.execute(
        "CREATE INDEX ix_drug_catalog_product_name_lower "
        "ON drug_catalog (lower(product_name) text_pattern_ops)"
    )
    op.execute(
        "CREATE INDEX ix_drug_catalog_active_lower "
        "ON drug_catalog (lower(active_ingredients) text_pattern_ops)"
    )


def downgrade() -> None:
    op.drop_index("ix_drug_catalog_active_lower", table_name="drug_catalog")
    op.drop_index("ix_drug_catalog_product_name_lower", table_name="drug_catalog")
    op.drop_table("drug_catalog")
