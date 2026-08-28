"""products cache (Open Food Facts, keyed by barcode)

Revision ID: a1c0ffee0004
Revises: a1c0ffee0003
Create Date: 2026-08-28 00:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "a1c0ffee0004"
down_revision: Union[str, None] = "a1c0ffee0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "products",
        sa.Column("barcode", sa.String(length=14), nullable=False),
        sa.Column("off_status", sa.String(length=10), nullable=False),
        sa.Column("name", sa.String(length=300), nullable=True),
        sa.Column("brand", sa.String(length=200), nullable=True),
        sa.Column("ingredients_text", sa.Text(), nullable=True),
        sa.Column(
            "ingredients",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'[]'::jsonb"),
            nullable=False,
        ),
        sa.Column(
            "nutriments",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.Column("serving_size", sa.String(length=80), nullable=True),
        sa.Column("image_url", sa.String(length=500), nullable=True),
        sa.Column(
            "source", sa.String(length=40), server_default=sa.text("'openfoodfacts'"), nullable=False
        ),
        sa.Column("raw", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("refreshed_at", sa.DateTime(timezone=True), nullable=False),
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
        sa.PrimaryKeyConstraint("barcode"),
    )
    op.create_index("ix_products_refreshed_at", "products", ["refreshed_at"])


def downgrade() -> None:
    op.drop_index("ix_products_refreshed_at", table_name="products")
    op.drop_table("products")
