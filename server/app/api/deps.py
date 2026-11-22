"""API 공통 의존성: DB 세션 · 현재 사용자.

현재 사용자는 로그인 토큰(Authorization: Bearer)으로 찾는다 (app/api/token.py).
토큰이 없거나 틀리면 401이다.
"""

from typing import Annotated

from fastapi import Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.token import get_token_user
from app.db.session import get_db
from app.models import User

DbDep = Annotated[Session, Depends(get_db)]

get_current_user = get_token_user
UserDep = Annotated[User, Depends(get_current_user)]


def get_writing_user(db: DbDep, user: UserDep) -> User:
    """데이터를 바꾸는 요청용. 사용자 행을 잠가서 같은 사용자의 쓰기 요청을 한 줄로 세운다.

    "있는지 확인 → 저장" 사이에 다른 요청이 끼어들면 같은 과목이 두 번 생기거나
    현재 학기 · 학기 중복 제약에 걸려 500이 난다 (버튼 두 번 누르기, 앱의 재요청).
    잠금은 커밋 · 롤백 때 풀린다. FOR NO KEY UPDATE라 판서 저장처럼
    이 사용자를 외래 키로 가리키는 INSERT는 막지 않는다.

    - 쓰기 요청은 시작할 때 자기 사용자 행을 잠금. 같은 사용자의 쓰기 요청 두 번째는
      첫 번째가 커밋하거나 롤백할 때까지 기다림.
      그 결과 "확인 → 저장"이 한 줄로 실행된다 -> 경쟁상태 방지
    - 사용자마다 따로 잠그므로 다른 사용자끼리는 서로 막지 않음
    - FOR UPDATE가 아니라 FOR NO KEY UPDATE인 이유: Postgres에서 captures 행을 INSERT하면,
      외래 키 검사 때문에 가리키는 users 행에 FOR KEY SHARE 잠금이 걸립니다.
      FOR UPDATE는 이 잠금과 충돌하지만 FOR NO KEY UPDATE는 충돌하지 않습니다.
      그래서 잠금을 쥔 같은 트랜잭션은 물론이고 워커 쪽 INSERT도 막히지 않습니다.
    - 잠금은 별도 해제 코드가 없고, 트랜잭션이 끝날 때 자동으로 풀림
    """
    db.execute(select(User.id).where(User.id == user.id).with_for_update(key_share=True))
    return user


WriteUserDep = Annotated[User, Depends(get_writing_user)]
