"""학사일정 웹 검색 기록 (#173)

같은 학교 · 학기 다시 찾기 간격(하루)과 하루 전체 검색 수 제한에 쓴다.
메모리에만 두면 서버를 다시 켤 때마다 기록이 사라져 같은 학교를 또 검색한다.

Revision ID: 0004
Revises: 0003
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0004"
down_revision: str | Sequence[str] | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "calendar_searches",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("school", sa.String(), nullable=False),
        sa.Column("year", sa.Integer(), nullable=False),
        sa.Column(
            "term",
            postgresql.ENUM(
                "first", "summer", "second", "winter", name="semester_term", create_type=False
            ),
            nullable=False,
        ),
        sa.Column(
            "searched_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_calendar_searches")),
    )
    op.create_index(
        "ix_calendar_searches_key",
        "calendar_searches",
        ["school", "year", "term", "searched_at"],
    )
    op.create_index("ix_calendar_searches_searched_at", "calendar_searches", ["searched_at"])


def downgrade() -> None:
    op.drop_index("ix_calendar_searches_searched_at", table_name="calendar_searches")
    op.drop_index("ix_calendar_searches_key", table_name="calendar_searches")
    op.drop_table("calendar_searches")
