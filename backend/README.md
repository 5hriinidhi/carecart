# CareCart backend (FastAPI)

## Stack
FastAPI 0.115 · SQLAlchemy 2.0 · Alembic · psycopg 3 · PostgreSQL 15 · pymilvus 2.5 · PyJWT · bcrypt

## Run with Docker (recommended)

```bash
cp .env.example .env                              # from repo root: copy backend\.env.example backend\.env
docker compose up -d --build                      # runs from repo root; postgres + backend
docker compose exec backend alembic upgrade head
```

- API docs: http://localhost:8000/docs
- Health:   http://localhost:8000/health → `{"status":"ok","db":"connected"}` (503 + reason if the DB is down)

## Run without Docker

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate            # Windows  (source .venv/bin/activate elsewhere)
pip install -r requirements.txt
cp .env.example .env              # POSTGRES_HOST stays "localhost"
docker compose up -d postgres     # just the DB (from repo root)
alembic upgrade head
uvicorn app.main:app --reload
```

## Configuration

`app/core/config.py` defines a typed `Settings` (pydantic-settings). Import the
single cached instance — `from app.core.config import settings` — everywhere;
never read `os.environ` directly.

- **Connection string**: composed as
  `postgresql+psycopg://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}`,
  or `DATABASE_URL` verbatim if set. `docker-compose.yml` overrides `POSTGRES_HOST=postgres`.
- **Fail-fast**: if a required var (`POSTGRES_*`) is empty, or — with
  `ENVIRONMENT=production` — `JWT_SECRET` is unset or a third-party key is
  missing, importing the module raises `ConfigError` naming each offending
  variable (not a `KeyError` / raw `ValidationError`) and the process exits.
- **Optional keys** (`OTP_PROVIDER_API_KEY`, `CLAUDE_API_KEY`, `OPENFDA_API_KEY`,
  `USDA_FDC_API_KEY`): allowed to be blank in dev. On startup `main.py` logs
  which are present vs missing — by name, never the value — and which feature
  each missing key degrades. `sqlalchemy_url_safe` masks the DB password for logs.

## Migrations

```bash
docker compose exec backend alembic revision --autogenerate -m "add x"
docker compose exec backend alembic upgrade head
docker compose exec backend alembic downgrade -1
```

`alembic/env.py` uses `settings.sqlalchemy_url` (the same URL the app uses) and
imports `app.models` so autogenerate sees every table. Add new models to
`app/models/__init__.py` (or import them there).

## Layout

```
Dockerfile             python:3.11-slim
app/
  main.py              FastAPI app, CORS, router mount, lifespan, GET /health (DB readiness)
  core/config.py       Settings (pydantic-settings, reads .env); composes sqlalchemy_url
  core/security.py     bcrypt hashing + JWT encode/decode
  db/base.py           DeclarativeBase + TimestampMixin
  db/session.py        engine + SessionLocal + get_db dependency
  models/__init__.py   User, Profile, Medication, ScanHistory
  api/deps.py          DbSession, get_current_user / CurrentUser
  api/v1/router.py      aggregate v1 router  (add feature routers here)
  api/v1/routes/        endpoint modules (health.py so far)
  vector/milvus_client.py   lazy MilvusClient helper
```

## Next

- `api/v1/routes/auth.py` — phone + OTP -> JWT (see onboarding turn 2a)
- `api/v1/routes/profiles.py`, `medications.py`, `scans.py`
- Load `../gradient-ascend-mobile-app/project/dataset/data_prep/*.csv`
  (risk_compounds, food_risk_tags, drug_classes, interaction_rules) into
  Postgres + Milvus via a seed script.

## Lint / test

```bash
ruff check app
ruff format app
pytest
```
