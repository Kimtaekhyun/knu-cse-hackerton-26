"""카카오 토큰 확인 (카카오 API는 가짜). DB 없이 돈다."""

import pytest

from app.services.social_auth import KakaoAuthError, KakaoUnavailable, fetch_profile
from tests.auth.conftest import APP_ID


def test_reads_profile(kakao):
    profile = fetch_profile(kakao.client(), "kakao-token", APP_ID)
    assert (profile.id, profile.nickname, profile.email) == ("3001", "판서왕", "user@example.com")
    assert kakao.tokens == ["Bearer kakao-token", "Bearer kakao-token"]


def test_token_from_other_app_is_rejected(kakao):
    kakao.app_id = 9999999
    with pytest.raises(KakaoAuthError):
        fetch_profile(kakao.client(), "kakao-token", APP_ID)


@pytest.mark.parametrize("status", [400, 401])
def test_rejected_token(kakao, status):
    kakao.status = status
    with pytest.raises(KakaoAuthError):
        fetch_profile(kakao.client(), "kakao-token", APP_ID)


@pytest.mark.parametrize("status", [500, 502, 503])
def test_kakao_server_error(kakao, status):
    kakao.status = status
    with pytest.raises(KakaoUnavailable):
        fetch_profile(kakao.client(), "kakao-token", APP_ID)


def test_timeout(kakao):
    kakao.timeout = True
    with pytest.raises(KakaoUnavailable):
        fetch_profile(kakao.client(), "kakao-token", APP_ID)


def test_no_consent_gives_no_nickname_and_email(kakao):
    kakao.account = {}
    profile = fetch_profile(kakao.client(), "kakao-token", APP_ID)
    assert (profile.nickname, profile.email) == (None, None)


def test_unverified_email_is_ignored(kakao):
    kakao.account["is_email_verified"] = False
    assert fetch_profile(kakao.client(), "kakao-token", APP_ID).email is None
