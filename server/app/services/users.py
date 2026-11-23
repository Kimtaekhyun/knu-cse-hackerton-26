"""내 계정(프로필 · 알림 설정) 저장 규칙.

라우터(app/api/v1/me.py)는 요청 확인만 하고 실제 저장은 여기서 한다.
"""

from sqlalchemy.orm import Session

from app.models import User, UserSettings
from app.schemas.me import ProfileUpdate, SettingsUpdate
from app.services import academic_calendar


def update_profile(db: Session, user: User, changes: ProfileUpdate) -> User:
    """보낸 칸만 바꾼다. 학교가 빈 값이면 비운다(None)."""
    sent = changes.model_fields_set
    if "name" in sent:
        user.name = changes.name
    if "school" in sent:
        user.school = changes.school or None
    db.commit()
    if "school" in sent and user.school:
        # 새 학교 학사일정이 없으면 미리 뒤에서 찾아 둔다 (#173). 저장은 기다리지 않는다
        academic_calendar.calendar_for(db, user)
    return user


def update_settings(db: Session, user: User, changes: SettingsUpdate) -> UserSettings:
    """보낸 알림만 바꾼다. 설정 행이 없는 사용자는 기본값(모두 켜짐)으로 만든 뒤 바꾼다.

    같은 사용자의 요청은 WriteUserDep 잠금으로 한 줄로 서므로 행이 두 번 만들어지지 않는다.
    """
    if user.settings is None:
        user.settings = UserSettings(notify_unmoved=True, notify_exam=True)
    for field in changes.model_fields_set:
        setattr(user.settings, field, getattr(changes, field))
    db.commit()
    return user.settings
