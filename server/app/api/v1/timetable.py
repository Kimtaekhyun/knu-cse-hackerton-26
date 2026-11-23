"""시간표 인식 API. 에브리타임 캡처에서 과목 후보만 뽑고 저장하지 않는다.

저장은 학기 API(PUT /semesters/timetable · PUT /semesters/{id}/timetable)가 한다.
"""

from typing import Annotated

from fastapi import APIRouter, File, HTTPException, UploadFile

from app.api.deps import UserDep
from app.schemas.timetable import TimetableParseResult
from app.services import timetable_ocr
from app.services.llm import LLMError

router = APIRouter(prefix="/timetable", tags=["timetable"])

# HEIC는 받지 않는다. 서버(Pillow)가 열 수 없어 칸 색 보정 · Claude 변환이 안 되고,
# iPad 앱은 올리기 전에 JPEG로 바꿔 보내므로 막아도 앱 사용자는 영향이 없다
ALLOWED_TYPES = {"image/png", "image/jpeg", "image/webp"}
MAX_BYTES = 10 * 1024 * 1024


@router.post("/parse", response_model=TimetableParseResult)
def parse(image: Annotated[UploadFile, File()], user: UserDep):
    """에브리타임 시간표 캡처를 받아 과목 후보를 돌려준다.

    부를 때마다 AI를 쓰므로 로그인한 사용자만 받는다 (#128). 토큰이 없거나 틀리면
    본문을 실행하기 전에 401로 끝나서 AI를 부르지 않는다. 읽기만 해서 WriteUserDep은 쓰지 않는다.
    AI 호출이 오래 막히므로 async가 아닌 일반 함수로 둔다 (FastAPI가 스레드에서 돌린다).
    """
    if image.content_type not in ALLOWED_TYPES:
        raise HTTPException(415, "이미지 파일(PNG, JPEG, WEBP)만 올릴 수 있어요.")
    data = image.file.read(MAX_BYTES + 1)
    if not data:
        raise HTTPException(400, "빈 파일이에요.")
    if len(data) > MAX_BYTES:
        raise HTTPException(413, "이미지가 10MB를 넘어요.")
    try:
        subjects = timetable_ocr.parse_timetable(data, image.content_type)
    except LLMError as error:
        raise HTTPException(502, str(error)) from error
    return TimetableParseResult(subjects=subjects)
