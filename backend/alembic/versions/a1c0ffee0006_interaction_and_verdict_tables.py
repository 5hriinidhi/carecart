"""food-drug interaction + severity scoring reference tables (Phase 4.4)

Revision ID: a1c0ffee0006
Revises: a1c0ffee0005
Create Date: 2026-08-28 00:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a1c0ffee0006"
down_revision: Union[str, None] = "a1c0ffee0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "interaction_rules",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("drug_class", sa.String(length=80), nullable=False),
        sa.Column("risk_compound", sa.String(length=48), nullable=False),
        sa.Column("severity", sa.String(length=12), nullable=False),
        sa.Column("mechanism", sa.Text(), nullable=True),
        sa.Column("dietary_guidance", sa.Text(), nullable=True),
        sa.Column("evidence_strength", sa.String(length=24), nullable=True),
        sa.Column("example_drugs", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(
            ["risk_compound"], ["risk_compounds.risk_compound"], ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_interaction_rules_drug_class", "interaction_rules", ["drug_class"])
    op.create_index(
        "ix_interaction_rules_risk_compound", "interaction_rules", ["risk_compound"]
    )

    op.create_table(
        "drug_class_lookup",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("active_ingredient", sa.String(length=120), nullable=False),
        sa.Column("drug_class", sa.String(length=80), nullable=False),
        sa.Column("source", sa.String(length=16), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_drug_class_lookup_active_ingredient",
        "drug_class_lookup",
        ["active_ingredient"],
    )

    op.create_table(
        "drug_class_stem_rules",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("ordinal", sa.Integer(), nullable=False),
        sa.Column("pattern", sa.String(length=40), nullable=False),
        sa.Column("position", sa.String(length=8), nullable=False),
        sa.Column("drug_class", sa.String(length=80), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )

    op.create_table(
        "condition_diet_rules",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("condition", sa.String(length=80), nullable=False),
        sa.Column("kind", sa.String(length=20), nullable=False),
        sa.Column("nutrient_key", sa.String(length=48), nullable=True),
        sa.Column("ceiling_per_100g", sa.Float(), nullable=True),
        sa.Column("risk_compound", sa.String(length=48), nullable=True),
        sa.Column("severity", sa.String(length=12), nullable=False),
        sa.Column("guidance", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(
            ["risk_compound"], ["risk_compounds.risk_compound"], ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_condition_diet_rules_condition", "condition_diet_rules", ["condition"]
    )

    op.create_table(
        "allergen_aliases",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("alias", sa.String(length=80), nullable=False),
        sa.Column("risk_compound", sa.String(length=48), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(
            ["risk_compound"], ["risk_compounds.risk_compound"], ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_allergen_aliases_alias", "allergen_aliases", ["alias"])


def downgrade() -> None:
    op.drop_index("ix_allergen_aliases_alias", table_name="allergen_aliases")
    op.drop_table("allergen_aliases")
    op.drop_index("ix_condition_diet_rules_condition", table_name="condition_diet_rules")
    op.drop_table("condition_diet_rules")
    op.drop_table("drug_class_stem_rules")
    op.drop_index(
        "ix_drug_class_lookup_active_ingredient", table_name="drug_class_lookup"
    )
    op.drop_table("drug_class_lookup")
    op.drop_index(
        "ix_interaction_rules_risk_compound", table_name="interaction_rules"
    )
    op.drop_index("ix_interaction_rules_drug_class", table_name="interaction_rules")
    op.drop_table("interaction_rules")
