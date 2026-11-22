"""내 계정(프로필) 저장 규칙.

라우터(app/api/v1/me.py)는 요청 확인만 하고 실제 저장은 여기서 한다.
"""

from sqlalchemy.orm import Session

from app.models import User
from app.schemas.me import ProfileUpdate


def update_profile(db: Session, user: User, changes: ProfileUpdate) -> User:
    """보낸 칸만 바꾼다. 학교가 빈 값이면 비운다(None)."""
    sent = changes.model_fields_set
    if "name" in sent:
        user.name = changes.name
    if "school" in sent:
        user.school = changes.school or None
    db.commit()
    return user
