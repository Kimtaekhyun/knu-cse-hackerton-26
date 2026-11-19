"""로그인한 카카오 사용자를 우리 사용자로 찾거나 새로 만든다."""

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import AuthProvider, User, UserSettings
from app.services.social_auth import KakaoProfile

DEFAULT_NAME = "사용자"  # 닉네임 제공에 동의하지 않은 경우
NAME_MAX = 50


def _find(db: Session, provider_uid: str) -> User | None:
    return db.scalars(
        select(User).where(User.provider == AuthProvider.kakao, User.provider_uid == provider_uid)
    ).first()


def login_kakao(db: Session, profile: KakaoProfile) -> tuple[User, bool]:
    """(사용자, 새로 만들었는지)를 돌려준다. 이미 있는 사용자의 이름 · 이메일은 바꾸지 않는다
    (앱에서 고친 이름을 카카오 닉네임으로 덮어쓰지 않게)."""
    user = _find(db, profile.id)
    if user:
        return user, False
    name = (profile.nickname or "").strip()[:NAME_MAX] or DEFAULT_NAME
    user = User(
        provider=AuthProvider.kakao, provider_uid=profile.id, email=profile.email, name=name
    )
    user.settings = UserSettings()
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        # 같은 카카오 계정으로 첫 로그인 요청이 동시에 두 번 온 경우. 먼저 만든 사용자를 쓴다
        db.rollback()
        user = _find(db, profile.id)
        if user is None:
            raise
        return user, False
    return user, True
