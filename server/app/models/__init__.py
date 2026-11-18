"""모든 모델을 한곳에서 import한다. alembic/env.py가 이 모듈을 import해서 테이블 목록을 얻는다."""

from app.models.capture import Capture, Card
from app.models.enums import AuthProvider, CaptureStatus, CardType, SemesterTerm
from app.models.semester import AcademicCalendar, Semester
from app.models.subject import Subject, SubjectSlot
from app.models.user import User, UserSettings

__all__ = [
    "AcademicCalendar",
    "AuthProvider",
    "Capture",
    "CaptureStatus",
    "Card",
    "CardType",
    "Semester",
    "SemesterTerm",
    "Subject",
    "SubjectSlot",
    "User",
    "UserSettings",
]
