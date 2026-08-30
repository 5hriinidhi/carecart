"""food catalog (searchable everyday-food dataset)

Revision ID: a1c0ffee0012
Revises: a1c0ffee0011
Create Date: 2026-08-30 00:00:01.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "a1c0ffee0012"
down_revision: Union[str, None] = "a1c0ffee0011"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "food_catalog",
        sa.Column("id", sa.Integer(), sa.Identity(), nullable=False),
        sa.Column("name", sa.String(length=300), nullable=False),
        sa.Column("kind", sa.String(length=12), nullable=False),
        sa.Column("brand", sa.String(length=200), nullable=True),
        sa.Column("category", sa.String(length=200), nullable=True),
        sa.Column("ingredients_text", sa.Text(), nullable=True),
        sa.Column("diet", sa.String(length=40), nullable=True),
        sa.Column("course", sa.String(length=60), nullable=True),
        sa.Column("region", sa.String(length=60), nullable=True),
        sa.Column("serving_size", sa.String(length=80), nullable=True),
        sa.Column(
            "nutriments",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_food_catalog_name", "food_catalog", ["name"])
    op.execute(
        "CREATE INDEX ix_food_catalog_name_lower "
        "ON food_catalog (lower(name) text_pattern_ops)"
    )


def downgrade() -> None:
    op.drop_index("ix_food_catalog_name_lower", table_name="food_catalog")
    op.drop_index("ix_food_catalog_name", table_name="food_catalog")
    op.drop_table("food_catalog")
