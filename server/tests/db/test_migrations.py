"""데이터를 바꾸는 마이그레이션이 기존 데이터를 제대로 옮기는지."""

import importlib.util
from pathlib import Path

from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import select, text

from app.models import Capture, Subject
from tests.db.factories import make_capture, make_semester, make_subject, make_user

VERSIONS = Path(__file__).resolve().parents[2] / "alembic" / "versions"


def run_upgrade(db, filename: str) -> None:
    spec = importlib.util.spec_from_file_location(filename, VERSIONS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with Operations.context(MigrationContext.configure(db.connection())):
        module.upgrade()


def test_0003_merges_duplicate_subjects(db):
    """예전 동시 요청으로 생긴 중복 과목: 가장 먼저 만든 과목만 남기고 판서는 그쪽으로 모은다"""
    db.execute(text("ALTER TABLE subjects DROP CONSTRAINT uq_subjects_semester_id_name"))
    user = make_user(db)
    semester = make_semester(db, user)
    other = make_semester(db, user, year=2025, is_current=False)
    first = make_subject(db, semester, name="자료구조")
    second = make_subject(db, semester, name="자료구조")
    single = make_subject(db, semester, name="이산수학")
    elsewhere = make_subject(db, other, name="자료구조")  # 다른 학기는 중복 아님
    on_first = make_capture(db, user, semester, first)
    on_second = make_capture(db, user, semester, second)
    second_id = second.id  # 지워진 뒤에는 객체에서 읽을 수 없으므로 미리 꺼내 둔다

    run_upgrade(db, "0003_subjects_unique_name.py")

    db.expire_all()
    remaining = set(db.scalars(select(Subject.id)).all())
    assert {first.id, single.id, elsewhere.id} <= remaining
    assert second_id not in remaining
    assert db.get(Capture, on_first.id).subject_id == first.id
    assert db.get(Capture, on_second.id).subject_id == first.id
