"""API 공통 의존성: DB 세션 · 현재 사용자.

로그인이 아직 없어서 사용자는 임시로 이렇게 정한다.
- `X-User-Id` 헤더가 있으면 그 사용자 (없는 id면 401)
- 헤더가 없으면 개발용 사용자 1명 (처음 요청할 때 만든다)
로그인 API가 생기면 get_current_user만 토큰 확인으로 바꾸면 된다.
"""

import uuid
from typing import Annotated

from fastapi import Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models import AuthProvider, User, UserSettings

DEV_USER_UID = "dev@pansoham.local"

DbDep = Annotated[Session, Depends(get_db)]


def _find_dev_user(db: Session) -> User | None:
    return db.scalars(
        select(User).where(User.provider == AuthProvider.email, User.provider_uid == DEV_USER_UID)
    ).first()


def _dev_user(db: Session) -> User:
    user = _find_dev_user(db)
    if user:
        return user
    user = User(
        provider=AuthProvider.email,
        provider_uid=DEV_USER_UID,
        email=DEV_USER_UID,
        name="개발용",
        school="경북대학교",
    )
    user.settings = UserSettings()
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        # 첫 요청 두 개가 동시에 만들려고 한 경우. 먼저 만든 사용자를 쓴다
        db.rollback()
        return _find_dev_user(db)
    return user


def get_current_user(db: DbDep, x_user_id: Annotated[uuid.UUID | None, Header()] = None) -> User:
    if x_user_id is None:
        return _dev_user(db)
    user = db.get(User, x_user_id)
    if user is None:
        raise HTTPException(401, "로그인이 필요해요.")
    return user


UserDep = Annotated[User, Depends(get_current_user)]


def get_writing_user(db: DbDep, user: UserDep) -> User:
    """데이터를 바꾸는 요청용. 사용자 행을 잠가서 같은 사용자의 쓰기 요청을 한 줄로 세운다.

    "있는지 확인 → 저장" 사이에 다른 요청이 끼어들면 같은 과목이 두 번 생기거나
    현재 학기 · 학기 중복 제약에 걸려 500이 난다 (버튼 두 번 누르기, 앱의 재요청).
    잠금은 커밋 · 롤백 때 풀린다. FOR NO KEY UPDATE라 판서 저장처럼
    이 사용자를 외래 키로 가리키는 INSERT는 막지 않는다.
    """
    db.execute(select(User.id).where(User.id == user.id).with_for_update(key_share=True))
    return user


WriteUserDep = Annotated[User, Depends(get_writing_user)]
