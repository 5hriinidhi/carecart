"""ingredient risk resolution: static reference tables + unresolved queue (Phase 4.3)

Revision ID: a1c0ffee0005
Revises: a1c0ffee0004
Create Date: 2026-08-28 00:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a1c0ffee0005"
down_revision: Union[str, None] = "a1c0ffee0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "risk_compounds",
        sa.Column("risk_compound", sa.String(length=48), nullable=False),
        sa.Column("display_name", sa.String(length=120), nullable=False),
        sa.Column("category", sa.String(length=32), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("typical_food_sources", sa.Text(), nullable=True),
        sa.Column("why_it_matters_for_drugs", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("risk_compound"),
    )

    op.create_table(
        "ingredient_risk_aliases",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("alias", sa.String(length=160), nullable=False),
        sa.Column("risk_compound", sa.String(length=48), nullable=True),
        sa.Column("match_type", sa.String(length=12), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=True),
        sa.Column("source", sa.String(length=16), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("rationale", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(
            ["risk_compound"], ["risk_compounds.risk_compound"], ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_ingredient_risk_aliases_alias", "ingredient_risk_aliases", ["alias"]
    )

    op.create_table(
        "risk_nutrient_thresholds",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("risk_compound", sa.String(length=48), nullable=False),
        sa.Column("nutrient_key", sa.String(length=48), nullable=False),
        sa.Column("basis", sa.String(length=16), nullable=False),
        sa.Column("min_value", sa.Float(), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.Column("method", sa.String(length=16), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=True),
        sa.Column("rationale", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(
            ["risk_compound"], ["risk_compounds.risk_compound"], ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_risk_nutrient_thresholds_nutrient_key",
        "risk_nutrient_thresholds",
        ["nutrient_key"],
    )

    op.create_table(
        "food_risk_tags",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("food_id", sa.String(length=16), nullable=False),
        sa.Column("risk_compound", sa.String(length=48), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=True),
        sa.Column("method", sa.String(length=24), nullable=True),
        sa.ForeignKeyConstraint(
            ["risk_compound"], ["risk_compounds.risk_compound"], ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_food_risk_tags_food_id", "food_risk_tags", ["food_id"])

    op.create_table(
        "unresolved_ingredients",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("ingredient_text", sa.String(length=200), nullable=False),
        sa.Column("normalized_text", sa.String(length=200), nullable=False),
        sa.Column("sample_product", sa.String(length=200), nullable=True),
        sa.Column(
            "times_seen", sa.Integer(), server_default=sa.text("1"), nullable=False
        ),
        sa.Column(
            "status",
            sa.String(length=12),
            server_default=sa.text("'pending'"),
            nullable=False,
        ),
        sa.Column(
            "first_seen_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "last_seen_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_unresolved_ingredients_normalized_text",
        "unresolved_ingredients",
        ["normalized_text"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_unresolved_ingredients_normalized_text",
        table_name="unresolved_ingredients",
    )
    op.drop_table("unresolved_ingredients")
    op.drop_index("ix_food_risk_tags_food_id", table_name="food_risk_tags")
    op.drop_table("food_risk_tags")
    op.drop_index(
        "ix_risk_nutrient_thresholds_nutrient_key",
        table_name="risk_nutrient_thresholds",
    )
    op.drop_table("risk_nutrient_thresholds")
    op.drop_index(
        "ix_ingredient_risk_aliases_alias", table_name="ingredient_risk_aliases"
    )
    op.drop_table("ingredient_risk_aliases")
    op.drop_table("risk_compounds")
