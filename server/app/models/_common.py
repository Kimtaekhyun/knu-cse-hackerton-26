"""모델 공통 컬럼."""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, Uuid, func, text
from sqlalchemy.orm import Mapped, mapped_column


def uuid_pk() -> Mapped[uuid.UUID]:
    return mapped_column(
        Uuid, primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()")
    )


def created_at() -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), server_default=func.now())


# 자식 관계(설정 · 과목 · 시간 칸 · 카드)는
# cascade="all, delete-orphan", passive_deletes=True 로 둔다.
# 기본값이면 db.delete(부모) 때 SQLAlchemy가 자식의 외래 키를 비우려다 NOT NULL 오류가 난다.
# passive_deletes=True 면 자식을 불러오지 않고 DB의 ON DELETE 규칙에 맡긴다.
