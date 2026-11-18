"""모든 모델이 상속하는 기반 클래스."""

from sqlalchemy import MetaData
from sqlalchemy.orm import DeclarativeBase

# 제약 이름을 규칙대로 붙여서 마이그레이션에서 이름으로 찾고 지울 수 있게 한다
NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)
