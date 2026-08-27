# CareCart backend (FastAPI)

## Stack
FastAPI 0.115 · SQLAlchemy 2.0 · Alembic · psycopg 3 · PostgreSQL 15 · pymilvus 2.5 · PyJWT · bcrypt

## Run locally

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate            # Windows  (source .venv/bin/activate elsewhere)
pip install -r requirements.txt
copy .env.example .env            # then edit secrets

# start Postgres + Milvus (from repo root)
cd ../infra && docker compose up -d && cd ../backend

alembic upgrade head              # apply migrations (once there are any)
uvicorn app.main:app --reload
```

- API docs: http://localhost:8000/docs
- Health:   http://localhost:8000/api/v1/health  and  `/health/db`

## Migrations

```bash
alembic revision --autogenerate -m "add x"   # needs Postgres running
alembic upgrade head
alembic downgrade -1
```

`alembic/env.py` is wired to `app.core.config.settings.database_url` and
`app.db.base.Base.metadata`, and imports `app.models` so autogenerate sees every
table. Add new models to `app/models/__init__.py` (or import them there).

## Layout

```
app/
  main.py              FastAPI app, CORS, router mount, lifespan
  core/config.py       Settings (pydantic-settings, reads .env)
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
