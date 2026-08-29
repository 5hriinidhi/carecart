"""users.timezone — learned local IANA tz for analytics bucketing (Phase 5.2)

Revision ID: a1c0ffee0009
Revises: a1c0ffee0008
Create Date: 2026-08-29 00:00:00.000000
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a1c0ffee0009"
down_revision: Union[str, None] = "a1c0ffee0008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("timezone", sa.String(length=64), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "timezone")
