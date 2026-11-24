# KNU CSE Hackathon 2026

Team repository for the Kyungpook National University School of Computer Science and Engineering hackathon (development period until 2026-11-24 12:00). Theme: services that CSE students need.

## Structure
- `ios/` — iPadOS SwiftUI app (`Pansoham.xcodeproj`). Sources are under `ios/Pansoham/`: `App/` (entry, routing), `Features/<screen group>/`, `Core/`, `DesignSystem/`. The project syncs the folder, so new files need no project edits.
- `server/` — FastAPI backend (skeleton only for now)
- `docs/` — Design documents
- `experiments/`, `samples/` — Experiment scripts and samples. Work on them **only on the test branch**; do not push them to main. Not subject to lint.
- `.venv/` — Local virtual environment (never commit)

## Development Commands
- Dependencies: use `uv` (`uv venv`, `uv pip install ...`)
- Lint: `uvx ruff check .`
- Format: `uvx ruff format .`
- A hook runs ruff automatically whenever a `.py` file is edited (except in experiments)
- Server (BE and FE alike): `docker compose up` from the repo root starts Postgres + the API at `localhost:8000`. On start the API runs `alembic upgrade head`, and `./server` is mounted with `--reload`, so code edits apply without rebuilding. Rebuild only after dependency changes: `docker compose up --build`. Reset the DB: `docker compose down -v`
- Server tests: `docker compose exec api uv run --no-sync pytest` (DB tests use the `pansoham_test` database and are skipped if Postgres is unreachable; `REQUIRE_DB=1` makes that a failure)
- New migration after changing models in `server/app/models/`: `docker compose exec api uv run --no-sync alembic revision --autogenerate -m "..."`, then review the file in `server/alembic/versions/`
- Settings come from the repo-root `.env` (see `.env.example`); `ANTHROPIC_API_KEY` is needed for timetable and board recognition (default `LLM_PROVIDER=claude`) and for academic calendar web search; `GEMINI_API_KEY` is only needed with `LLM_PROVIDER=gemini`

## Collaboration Rules
- Do not push directly to main. Branch → PR → merge after review. The user merges themselves.
- Branch names: `feat/…`, `fix/…`, `docs/…`
- Commit and PR titles follow conventional commit: `feat:`, `fix:`, `docs:`, `test:`, `chore:`, `ci:`, `refactor:`
- Never commit `.env` or API keys. List only the variable names in `.env.example`.

## Code Style
- Python 3.11, line length 100, configured in `pyproject.toml`
- Comments and documentation are written in Korean
