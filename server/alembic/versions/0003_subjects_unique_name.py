"""과목 이름 유니크: 같은 학기에 같은 이름 과목은 하나만 (#50)

제약을 걸기 전에 이미 생긴 중복을 정리한다.
가장 먼저 만든 과목을 남기고, 나머지 과목의 판서는 남는 과목으로 옮긴 뒤 지운다.
(시간표 저장 API의 중복 정리와 같은 규칙)

Revision ID: 0003
Revises: 0002
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0003"
down_revision: str | Sequence[str] | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 중복 과목 → 남길 과목 매핑 (학기 · 이름별로 가장 먼저 만든 과목을 남김)
    op.execute(
        """
        CREATE TEMP TABLE subject_dedup ON COMMIT DROP AS
        SELECT id AS duplicate_id, keep_id
        FROM (
            SELECT id,
                   first_value(id) OVER (
                       PARTITION BY semester_id, name ORDER BY created_at, id
                   ) AS keep_id
            FROM subjects
        ) ranked
        WHERE id <> keep_id
        """
    )
    op.execute(
        """
        UPDATE captures SET subject_id = d.keep_id
        FROM subject_dedup d
        WHERE captures.subject_id = d.duplicate_id
        """
    )
    op.execute("DELETE FROM subjects WHERE id IN (SELECT duplicate_id FROM subject_dedup)")
    op.execute("DROP TABLE subject_dedup")

    op.create_unique_constraint(
        op.f("uq_subjects_semester_id_name"), "subjects", ["semester_id", "name"]
    )


def downgrade() -> None:
    # 정리한 중복 과목은 되살리지 않는다
    op.drop_constraint(op.f("uq_subjects_semester_id_name"), "subjects", type_="unique")
