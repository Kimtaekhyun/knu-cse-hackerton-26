"""같은 사용자의 요청이 동시에 들어올 때 (버튼 두 번 누르기, 앱의 재요청).

다른 테스트처럼 한 트랜잭션 안에서 되돌리면 동시 요청을 흉내 낼 수 없어서,
요청마다 진짜 연결 · 커밋을 쓰고 끝나면 만든 사용자를 지운다 (학기 · 과목도 같이 지워진다).
"""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import delete, func, select
from sqlalchemy.orm import sessionmaker

from app.core.config import get_settings
from app.db.session import get_db
from app.main import app
from app.models import Capture, Semester, Subject, User
from tests.api.conftest import bearer
from tests.db.factories import make_user

N = 10


@pytest.fixture
def live(db_engine):
    """(client, 헤더). 요청마다 새 연결을 쓰고 실제로 커밋한다"""
    Session = sessionmaker(bind=db_engine, expire_on_commit=False)

    def get():
        with Session() as session:
            yield session

    with Session() as session:
        user_id = make_user(session).id
        session.commit()
    app.dependency_overrides[get_db] = get
    yield TestClient(app), bearer(user_id), Session
    app.dependency_overrides.clear()
    with Session() as session:
        session.execute(delete(User).where(User.id == user_id))
        session.commit()


def at_once(send) -> list[int]:
    """send를 N개 스레드에서 동시에 실행하고 상태 코드를 모은다"""
    barrier = Barrier(N)

    def run(_):
        barrier.wait()
        return send().status_code

    with ThreadPoolExecutor(N) as pool:
        return list(pool.map(run, range(N)))


def test_same_subject_added_at_once(live):
    client, auth, Session = live
    semester = client.post("/api/v1/semesters", json={"year": 2026, "term": "second"}, headers=auth)
    url = f"/api/v1/semesters/{semester.json()['id']}/subjects"

    codes = at_once(lambda: client.post(url, json={"name": "자료구조"}, headers=auth))
    assert sorted(codes) == [201] + [409] * (N - 1)
    with Session() as session:
        assert session.scalar(select(func.count()).where(Subject.name == "자료구조")) == 1


def test_timetable_saved_at_once(live):
    client, auth, Session = live
    semester = client.post("/api/v1/semesters", json={"year": 2026, "term": "second"}, headers=auth)
    semester_id = semester.json()["id"]
    url = f"/api/v1/semesters/{semester_id}/timetable"
    body = {"subjects": [{"name": "자료구조"}, {"name": "운영체제"}]}

    assert at_once(lambda: client.put(url, json=body, headers=auth)) == [200] * N
    with Session() as session:
        names = session.scalars(select(Subject.name).where(Subject.semester_id == semester_id))
        assert sorted(names) == ["운영체제", "자료구조"]


def test_same_semester_created_at_once(live):
    client, auth, Session = live
    body = {"year": 2026, "term": "second"}

    codes = at_once(lambda: client.post("/api/v1/semesters", json=body, headers=auth))
    assert sorted(codes) == [201] + [409] * (N - 1)


def test_current_semester_switched_at_once(live):
    client, auth, Session = live
    ids = [
        client.post("/api/v1/semesters", json={"year": 2026, "term": term}, headers=auth).json()[
            "id"
        ]
        for term in ("first", "summer", "second", "winter")
    ]
    turn = iter(range(N))

    def switch():
        return client.put(f"/api/v1/semesters/{ids[next(turn) % 4]}/current", headers=auth)

    assert at_once(switch) == [200] * N
    with Session() as session:
        assert session.scalar(select(func.count()).where(Semester.is_current)) == 1


def test_same_capture_resent_at_once(live, tmp_path, monkeypatch):
    """답을 못 받은 앱이 같은 판서 id로 여러 번 다시 보내도 판서는 하나만 생긴다"""
    client, auth, Session = live
    monkeypatch.setenv("MEDIA_DIR", str(tmp_path))
    get_settings.cache_clear()
    client.post("/api/v1/semesters", json={"year": 2026, "term": "second"}, headers=auth)
    capture_id = str(uuid4())

    def send():
        return client.post(
            "/api/v1/captures",
            headers=auth,
            data={"id": capture_id},
            files={"image": ("a.jpg", b"jpeg", "image/jpeg")},
        )

    codes = at_once(send)
    assert sorted(codes) == [200] * (N - 1) + [202]
    with Session() as session:
        assert session.scalar(select(func.count()).where(Capture.id == capture_id)) == 1
