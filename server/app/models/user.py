"""사용자 · 사용자 설정."""

import uuid
from datetime import datetime

from sqlalchemy import Enum, ForeignKey, UniqueConstraint, true
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models._common import created_at, uuid_pk
from app.models.enums import AuthProvider


class User(Base):
    __tablename__ = "users"
    __table_args__ = (UniqueConstraint("provider", "provider_uid"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    provider: Mapped[AuthProvider] = mapped_column(Enum(AuthProvider, name="auth_provider"))
    # 카카오 id / 이메일
    provider_uid: Mapped[str]
    # 카카오는 이메일 동의를 안 하면 없음
    email: Mapped[str | None]
    # email provider만
    password_hash: Mapped[str | None]
    name: Mapped[str]
    # academic_calendars.school과 같은 값으로 저장 (예: 경북대학교)
    school: Mapped[str | None]
    created_at: Mapped[datetime] = created_at()

    settings: Mapped["UserSettings | None"] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan", passive_deletes=True
    )


class UserSettings(Base):
    """가입할 때 기본값으로 만든다. 알림 예약은 앱에서 한다 (서버 푸시 없음)"""

    __tablename__ = "user_settings"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    # 옮기지 않은 판서 알림
    notify_unmoved: Mapped[bool] = mapped_column(server_default=true())
    # 시험 기간 알림
    notify_exam: Mapped[bool] = mapped_column(server_default=true())

    user: Mapped[User] = relationship(back_populates="settings")
