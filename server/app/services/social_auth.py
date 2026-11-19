"""카카오 로그인 확인. 앱이 카카오 SDK로 받은 access token으로 카카오에 직접 물어 사용자를 알아낸다.

1. 토큰 정보 보기(/v1/user/access_token_info): 토큰이 살아 있는지, 우리 앱(app_id)에서 받은 토큰인지
2. 사용자 정보 가져오기(/v2/user/me): 카카오 회원 번호 · 닉네임 · 이메일(동의한 경우만)
"""

from dataclasses import dataclass

import httpx

KAKAO_API = "https://kapi.kakao.com"
TIMEOUT = 5.0  # 초. 카카오가 이보다 늦으면 502로 돌려준다


class KakaoAuthError(Exception):
    """토큰이 틀렸거나 만료됐거나, 다른 앱에서 받은 토큰 (→ 401)"""


class KakaoUnavailable(Exception):
    """카카오 서버 오류 · 시간 초과 · 이상한 응답 (→ 502)"""


@dataclass(frozen=True)
class KakaoProfile:
    id: str
    nickname: str | None
    email: str | None


def _get(client: httpx.Client, path: str, access_token: str) -> dict:
    try:
        response = client.get(KAKAO_API + path, headers={"Authorization": f"Bearer {access_token}"})
    except httpx.HTTPError as error:
        raise KakaoUnavailable(f"카카오 요청 실패: {type(error).__name__}") from error
    if response.status_code in (400, 401):
        raise KakaoAuthError(f"카카오가 토큰을 거절함 ({response.status_code})")
    if response.status_code != 200:
        raise KakaoUnavailable(f"카카오 응답 {response.status_code}")
    try:
        data = response.json()
    except ValueError as error:
        raise KakaoUnavailable("카카오 응답이 JSON이 아님") from error
    if not isinstance(data, dict) or "id" not in data:
        raise KakaoUnavailable("카카오 응답에 id가 없음")
    return data


def fetch_profile(client: httpx.Client, access_token: str, app_id: int) -> KakaoProfile:
    """카카오 토큰을 확인하고 사용자 정보를 돌려준다. 실패하면 KakaoAuthError · KakaoUnavailable."""
    info = _get(client, "/v1/user/access_token_info", access_token)
    if info.get("app_id") != app_id:
        raise KakaoAuthError("다른 앱에서 받은 카카오 토큰")
    me = _get(client, "/v2/user/me", access_token)
    if str(me["id"]) != str(info["id"]):
        raise KakaoAuthError("토큰 정보와 사용자 정보의 회원 번호가 다름")

    account = me.get("kakao_account") or {}
    profile = account.get("profile") or {}
    nickname = profile.get("nickname") or (me.get("properties") or {}).get("nickname")
    # 유효하고 인증된 이메일만 쓴다 (동의하지 않았으면 email 자체가 없다)
    verified = account.get("is_email_valid") and account.get("is_email_verified")
    email = account.get("email") if verified else None
    return KakaoProfile(id=str(me["id"]), nickname=nickname, email=email)
