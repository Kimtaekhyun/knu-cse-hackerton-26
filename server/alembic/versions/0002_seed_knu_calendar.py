"""시드: 경북대학교 2026년 2학기 학사일정

출처: 경북대학교 학사일정 https://www.knu.ac.kr/wbbs/wbbs/user/yearSchedule/index.action?menu_idx=43
(2026-11-18 확인)
- "09.01(화)개강 (9.1.)"
- "10.21(수)중간고사 기간 (10.21.~10.27.)"
- "12.14(월)기말고사 기간 (12.14.~12.18.)"

Revision ID: 0002
Revises: 0001
"""

from collections.abc import Sequence
from datetime import date

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0002"
down_revision: str | Sequence[str] | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

KNU = {"school": "경북대학교", "year": 2026, "term": "second"}

calendars = sa.table(
    "academic_calendars",
    sa.column("school", sa.String),
    sa.column("year", sa.Integer),
    sa.column("term", postgresql.ENUM(name="semester_term", create_type=False)),
    sa.column("starts_on", sa.Date),
    sa.column("midterm_start", sa.Date),
    sa.column("final_start", sa.Date),
)


def upgrade() -> None:
    op.bulk_insert(
        calendars,
        [
            KNU
            | {
                "starts_on": date(2026, 9, 1),
                "midterm_start": date(2026, 10, 21),
                "final_start": date(2026, 12, 14),
            }
        ],
    )


def downgrade() -> None:
    op.execute(
        calendars.delete().where(
            calendars.c.school == KNU["school"],
            calendars.c.year == KNU["year"],
            calendars.c.term == KNU["term"],
        )
    )
