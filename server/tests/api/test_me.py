"""내 계정 API: GET /me · PATCH /me (이름 · 학교) · PATCH /me/settings (알림 설정)."""

import unicodedata

import pytest

from app.models import SemesterTerm, UserSettings
from tests.api.conftest import bearer
from tests.db.factories import make_semester, make_user

ME = "/api/v1/me"


def patch_me(client, auth, body):
    return client.patch(ME, json=body, headers=auth)


def get_me(client, auth):
    return client.get(ME, headers=auth).json()


# ---------- 조회 ----------


def test_get_me_returns_profile(client, auth, user):
    body = get_me(client, auth)
    assert body["id"] == str(user.id)
    assert (body["name"], body["school"]) == ("테스트", "경북대학교")


# ---------- 보낸 것만 바꾼다 ----------


def test_update_name_only_keeps_school(client, auth):
    response = patch_me(client, auth, {"name": "민석"})
    assert response.status_code == 200
    assert (response.json()["name"], response.json()["school"]) == ("민석", "경북대학교")


def test_update_school_only_keeps_name(client, auth):
    response = patch_me(client, auth, {"school": "서울대학교"})
    assert response.status_code == 200
    assert (response.json()["name"], response.json()["school"]) == ("테스트", "서울대학교")


def test_empty_body_changes_nothing(client, auth):
    response = patch_me(client, auth, {})
    assert response.status_code == 200
    assert (response.json()["name"], response.json()["school"]) == ("테스트", "경북대학교")


def test_update_is_kept_in_get_me(client, auth):
    patch_me(client, auth, {"name": "민석", "school": "서울대학교"})
    body = get_me(client, auth)
    assert (body["name"], body["school"]) == ("민석", "서울대학교")


# ---------- 이름 검사 ----------


def test_name_whitespace_is_trimmed(client, auth):
    assert patch_me(client, auth, {"name": "  민석  "}).json()["name"] == "민석"


def test_name_is_normalized_to_nfc(client, auth):
    # iPad 입력은 자모가 쪼개진 NFD로 올 수 있다
    nfd = unicodedata.normalize("NFD", "민석")
    assert patch_me(client, auth, {"name": nfd}).json()["name"] == "민석"


def test_name_of_50_characters_is_accepted(client, auth):
    assert patch_me(client, auth, {"name": "가" * 50}).status_code == 200


@pytest.mark.parametrize(
    "name",
    [
        "가" * 51,  # 너무 김
        "   ",  # 공백만 있으면 빈 이름
        "민\n석",  # 제어 문자
        "민\u0000석",  # NUL은 Postgres에 넣을 수 없음
        None,  # 이름은 비울 수 없다
    ],
)
def test_bad_name_is_422_and_unchanged(client, auth, name):
    assert patch_me(client, auth, {"name": name}).status_code == 422
    assert get_me(client, auth)["name"] == "테스트"


# ---------- 학교 검사 ----------


@pytest.mark.parametrize("school", ["", "   ", None])
def test_blank_school_clears_it(client, auth, school):
    response = patch_me(client, auth, {"school": school})
    assert response.status_code == 200
    assert response.json()["school"] is None


def test_school_whitespace_is_trimmed(client, auth):
    assert patch_me(client, auth, {"school": "  경북대학교 "}).json()["school"] == "경북대학교"


def test_school_not_in_calendar_is_accepted(client, auth):
    # 학사일정에 없는 학교도 받는다 (시험 기간 정보만 없음)
    assert patch_me(client, auth, {"school": "없는대학교"}).json()["school"] == "없는대학교"


def test_too_long_school_is_422(client, auth):
    assert patch_me(client, auth, {"school": "가" * 51}).status_code == 422


# ---------- 로그인 · 다른 사용자 ----------


def test_other_user_is_untouched(client, db, auth):
    other = make_user(db, name="다른사람", school="서울대학교")
    patch_me(client, auth, {"name": "민석", "school": None})
    body = get_me(client, bearer(other.id))
    assert (body["name"], body["school"]) == ("다른사람", "서울대학교")


def test_patch_without_token_is_401(client):
    assert client.patch(ME, json={"name": "민석"}).status_code == 401


# ---------- 알림 설정 (GET /me의 settings · PATCH /me/settings) ----------

SETTINGS = "/api/v1/me/settings"
DEFAULTS = {"notify_unmoved": True, "notify_exam": True}


def patch_settings(client, auth, body):
    return client.patch(SETTINGS, json=body, headers=auth)


def add_settings(db, user, **values) -> UserSettings:
    settings = UserSettings(user_id=user.id, **values)
    db.add(settings)
    db.flush()
    return settings


def test_get_me_without_settings_row_shows_defaults(client, auth):
    # make_user는 설정 행을 만들지 않는다 (예전 가입자도 이런 상태일 수 있다)
    assert get_me(client, auth)["settings"] == DEFAULTS


def test_get_me_shows_saved_settings(client, db, auth, user):
    add_settings(db, user, notify_unmoved=False)
    assert get_me(client, auth)["settings"] == {"notify_unmoved": False, "notify_exam": True}


def test_profile_update_response_includes_settings(client, auth):
    assert patch_me(client, auth, {"name": "민석"}).json()["settings"] == DEFAULTS


def test_update_one_setting_keeps_the_other(client, db, auth, user):
    add_settings(db, user, notify_unmoved=False)
    response = patch_settings(client, auth, {"notify_exam": False})
    assert response.status_code == 200
    assert response.json() == {"notify_unmoved": False, "notify_exam": False}


def test_update_settings_creates_row_when_missing(client, db, auth, user):
    response = patch_settings(client, auth, {"notify_unmoved": False})
    assert response.status_code == 200
    assert response.json() == {"notify_unmoved": False, "notify_exam": True}
    assert db.get(UserSettings, user.id) is not None


def test_settings_update_is_kept_in_get_me(client, auth):
    patch_settings(client, auth, {"notify_unmoved": False, "notify_exam": False})
    assert get_me(client, auth)["settings"] == {"notify_unmoved": False, "notify_exam": False}


def test_empty_settings_body_changes_nothing(client, db, auth, user):
    add_settings(db, user, notify_exam=False)
    assert patch_settings(client, auth, {}).json() == {"notify_unmoved": True, "notify_exam": False}


@pytest.mark.parametrize("body", [{"notify_exam": None}, {"notify_unmoved": None}])
def test_null_setting_is_422(client, auth, body):
    assert patch_settings(client, auth, body).status_code == 422


def test_settings_of_other_user_are_untouched(client, db, auth):
    other = make_user(db)
    add_settings(db, other)
    patch_settings(client, auth, {"notify_unmoved": False, "notify_exam": False})
    assert get_me(client, bearer(other.id))["settings"] == DEFAULTS


def test_patch_settings_without_token_is_401(client):
    assert client.patch(SETTINGS, json={"notify_exam": False}).status_code == 401


# ---------- 학교를 바꾸면 학사일정 미리 찾기 (#173) ----------


def test_new_school_calendar_is_searched_ahead(client, db, auth, user, calendar_lookups):
    make_semester(db, user)
    assert patch_me(client, auth, {"school": "부산대학교"}).status_code == 200
    assert calendar_lookups == [("부산대학교", 2026, SemesterTerm.second)]


def test_school_with_calendar_is_not_searched(client, db, auth, user, calendar_lookups):
    make_semester(db, user)
    patch_me(client, auth, {"school": "경북대학교"})  # 시드에 있는 학교 · 학기
    assert calendar_lookups == []


def test_name_change_does_not_search(client, db, auth, user, calendar_lookups):
    make_semester(db, user, year=2027, term=SemesterTerm.first)
    patch_me(client, auth, {"name": "민석"})
    assert calendar_lookups == []
