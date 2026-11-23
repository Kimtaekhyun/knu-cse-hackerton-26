"""로그인한 사용자를 우리 사용자로 찾거나 새로 만든다 (카카오 · 이메일).

같은 사람이 이메일 계정과 카카오 계정으로 나뉘지 않게 이메일로 겹치는지 본다 (#120).
- 이메일 가입: 같은 이메일의 계정(이메일 · 카카오)이 있으면 막는다
- 첫 카카오 로그인: 같은 이메일의 이메일 계정이 있으면 앱에 물어본다.
  이메일 가입은 메일 인증이 없어서, 아예 막으면 남이 내 이메일로 먼저 가입해
  진짜 주인의 카카오 가입을 막을 수 있기 때문이다
"""

from functools import cache

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.security import hash_password, verify_password
from app.models import AuthProvider, User, UserSettings
from app.schemas.auth import EmailSignupRequest
from app.services.social_auth import KakaoProfile

DEFAULT_NAME = "사용자"  # 닉네임 제공에 동의하지 않은 경우
NAME_MAX = 50


class EmailTaken(Exception):
    """가입하려는 이메일을 이미 쓰는 계정이 있음. provider는 그 계정의 로그인 방식"""

    def __init__(self, provider: AuthProvider):
        super().__init__(provider.value)
        self.provider = provider


class EmailAccountExists(Exception):
    """처음 로그인한 카카오 사용자와 같은 이메일의 이메일 계정이 있음.
    email은 소문자로 맞춘 그 이메일 (앱이 이메일 로그인 칸을 채울 때 쓴다)."""

    def __init__(self, email: str):
        super().__init__(email)
        self.email = email


def _find(db: Session, provider: AuthProvider, provider_uid: str) -> User | None:
    return db.scalars(
        select(User).where(User.provider == provider, User.provider_uid == provider_uid)
    ).first()


def _with_email(db: Session, email: str, provider: AuthProvider | None = None) -> list[User]:
    """그 이메일(대소문자 무시)을 쓰는 사용자.
    카카오 이메일은 받은 그대로 저장돼 있어 소문자로 바꿔 비교한다."""
    query = select(User).where(func.lower(User.email) == email.lower())
    if provider is not None:
        query = query.where(User.provider == provider)
    return list(db.scalars(query))


def _create(db: Session, user: User) -> User | None:
    """사용자와 기본 설정을 함께 만든다. 같은 (provider, provider_uid)가 이미 있으면 None"""
    user.settings = UserSettings()
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        return None
    return user


def login_kakao(
    db: Session, profile: KakaoProfile, allow_duplicate_email: bool = False
) -> tuple[User, bool]:
    """(사용자, 새로 만들었는지)를 돌려준다. 이미 있는 사용자의 이름 · 이메일은 바꾸지 않는다
    (앱에서 고친 이름을 카카오 닉네임으로 덮어쓰지 않게).

    처음 가입이고 같은 이메일의 이메일 계정이 있으면, allow_duplicate_email이 아닌 한
    만들지 않고 EmailAccountExists를 낸다.
    """
    user = _find(db, AuthProvider.kakao, profile.id)
    if user:
        return user, False
    if profile.email and not allow_duplicate_email:
        if _with_email(db, profile.email, AuthProvider.email):
            raise EmailAccountExists(profile.email.strip().lower())
    name = (profile.nickname or "").strip()[:NAME_MAX] or DEFAULT_NAME
    created = _create(
        db,
        User(provider=AuthProvider.kakao, provider_uid=profile.id, email=profile.email, name=name),
    )
    if created:
        return created, True
    # 같은 카카오 계정으로 첫 로그인 요청이 동시에 두 번 온 경우. 먼저 만든 사용자를 쓴다
    user = _find(db, AuthProvider.kakao, profile.id)
    if user is None:
        raise RuntimeError("카카오 사용자를 만들지도 찾지도 못했어요.")
    return user, False


def signup_email(db: Session, body: EmailSignupRequest) -> User:
    """이메일 가입. 이메일은 스키마에서 이미 공백 제거 · 소문자로 맞춰져 있다.
    같은 이메일의 계정이 있으면 EmailTaken (이메일 계정이 먼저)."""
    taken = {user.provider for user in _with_email(db, body.email)}
    if AuthProvider.email in taken or _find(db, AuthProvider.email, body.email):
        raise EmailTaken(AuthProvider.email)
    if AuthProvider.kakao in taken:
        raise EmailTaken(AuthProvider.kakao)
    user = _create(
        db,
        User(
            provider=AuthProvider.email,
            provider_uid=body.email,
            email=body.email,
            password_hash=hash_password(body.password),
            name=body.name,
        ),
    )
    if user is None:
        # 같은 이메일로 가입 요청이 동시에 두 번 온 경우
        raise EmailTaken(AuthProvider.email)
    return user


@cache
def _dummy_hash() -> str:
    return hash_password("no-such-user-password")


def login_email(db: Session, email: str, password: str) -> User | None:
    """이메일 · 비밀번호가 맞으면 사용자, 아니면 None.
    없는 이메일이어도 해시 확인을 한 번 돌려서 응답 시간으로 가입 여부가 드러나지 않게 한다."""
    user = _find(db, AuthProvider.email, email)
    if user is None:
        verify_password(password, _dummy_hash())
        return None
    return user if verify_password(password, user.password_hash) else None
