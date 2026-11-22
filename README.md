# 판서함

수업 중에 찍은 판서 사진을 과목별로 정리해 주는 iPad 앱입니다.
2026 경북대학교 컴퓨터학부 해커톤(주제: 컴퓨터학부 학생에게 필요한 서비스) 출품작입니다.

## 무엇을 하나요
- **시간표로 자동 분류**: 에브리타임 시간표 캡처를 올리면 과목이 등록됩니다. 이후 판서를 찍으면 촬영 시각에 맞는 과목 폴더로 들어가고, 맞는 수업이 없으면 미분류함에 남습니다.
- **판서를 카드로**: 올린 사진은 서버에서 화면 펴기 → AI로 내용 덩어리 찾기 → 카드 만들기 순서로 처리됩니다. 카드는 고치거나 되돌릴 수 있습니다.
- **메인 화면**: 지금 듣는 수업, 오늘 수업, 이번 주 판서, 시험까지 남은 기간을 한눈에 보여줍니다.
- **카카오 로그인**

## 구조

```
ios/      iPadOS SwiftUI 앱 (Pansoham.xcodeproj)
server/   FastAPI 백엔드 + PostgreSQL
docs/     설계 문서
```

| 구분 | 기술 |
|---|---|
| 앱 | SwiftUI, iPadOS 26 이상 |
| 서버 | Python 3.11, FastAPI, SQLAlchemy, Alembic, OpenCV |
| DB | PostgreSQL 17 |
| AI | Gemini(기본) 또는 Claude. `LLM_PROVIDER`로 선택 |

## 시작하기

### 1. 서버

Docker가 필요합니다.

```bash
cp .env.example .env   # 필요한 값 채우기 (아래 표 참고)
docker compose up      # Postgres + API (localhost:8000)
```

- 켤 때 `alembic upgrade head`가 자동으로 실행됩니다.
- `./server`가 컨테이너에 연결되어 있어 코드를 저장하면 서버가 다시 시작됩니다. 의존성을 바꿨을 때만 `docker compose up --build`로 다시 빌드합니다.
- DB를 비우려면 `docker compose down -v`
- API 문서: http://localhost:8000/docs

`.env`에 넣는 주요 값 (전체 목록과 설명은 `.env.example`):

| 변수 | 용도 |
|---|---|
| `GEMINI_API_KEY` | 시간표 · 판서 인식 (기본 AI) |
| `LLM_PROVIDER`, `ANTHROPIC_API_KEY` | Claude를 쓸 때 `LLM_PROVIDER=claude`와 함께 |
| `JWT_SECRET` | 로그인 토큰 서명 키 (32자 이상 무작위 값) |
| `KAKAO_APP_ID` | 카카오 로그인 |

AI 키가 없어도 서버는 뜹니다. 시간표 · 판서 인식만 동작하지 않습니다.

### 2. iPad 앱

1. `ios/Config/Local.xcconfig.example`을 복사해 `ios/Config/Local.xcconfig`를 만들고 내 값을 적습니다 (git에 올라가지 않음).
   - `DEVELOPMENT_TEAM`: 내 Apple 개발자 Team ID
   - `PRODUCT_BUNDLE_IDENTIFIER`: 사람마다 다른 번들 ID (예: `com.myname.pansoham`)
   - `API_BASE_URL`: 실기기에서만 필요. 서버를 띄운 Mac 주소 (예: `http:/$()/my-macbook.local:8000`). 시뮬레이터는 `localhost`를 쓰므로 지웁니다.
   - `KAKAO_NATIVE_APP_KEY`: 내 번들 ID를 등록한 카카오 네이티브 앱 키
2. `ios/Pansoham.xcodeproj`를 Xcode로 열고 iPad 시뮬레이터나 기기를 골라 실행합니다.

자세한 배경은 이슈 #22를 참고하세요.

## 개발

| 할 일 | 명령 |
|---|---|
| 린트 | `uvx ruff check .` |
| 포맷 | `uvx ruff format .` |
| 서버 테스트 | `docker compose exec api uv run --no-sync pytest` |
| 마이그레이션 생성 | `docker compose exec api uv run --no-sync alembic revision --autogenerate -m "..."` |

- 서버 테스트는 `pansoham_test` DB를 씁니다. Postgres에 붙지 못하면 DB 테스트를 건너뛰고, `REQUIRE_DB=1`이면 실패로 처리합니다.
- `server/app/models/`를 바꿨다면 마이그레이션을 만들고 `server/alembic/versions/`의 파일을 꼭 검토합니다.
- PR마다 CI가 ruff 검사와 서버 테스트를 돌립니다.

## 협업 규칙

- main에 바로 push하지 않습니다. 브랜치 → PR → 리뷰 후 머지
- 브랜치 이름: `feat/…`, `fix/…`, `docs/…`
- 커밋 · PR 제목: `feat:`, `fix:`, `docs:`, `test:`, `chore:`, `ci:`, `refactor:`
- `.env`와 API 키는 커밋하지 않습니다. 새 변수는 이름만 `.env.example`에 적습니다.
- 주석과 문서는 한국어로 씁니다.
