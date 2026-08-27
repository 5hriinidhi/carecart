# CareCart

Scan a food label, get a verdict that's checked against **your** medications,
conditions, allergies, and profile-derived nutrient ceilings — not a generic score.

Monorepo:

| Path | What |
|---|---|
| `mobile/` | Flutter app (Riverpod + go_router), targets Android & iOS (web enabled for fast local iteration) |
| `backend/` | FastAPI service (Python 3.11, SQLAlchemy 2 + Alembic, PostgreSQL, Milvus) + `Dockerfile` |
| `docker-compose.yml` | Postgres 15 + backend (this is the one you run) |
| `infra/docker-compose.yml` | vector stack — Milvus + deps + Attu UI (needed from Phase 3) |
| `gradient-ascend-mobile-app/` | The approved UI design (`CareCart App.dc.html`) — reference, the app must match it |
| `SETUP.md` | One-time toolchain setup + what's already installed on this machine |

---

## Run it locally

### Prerequisites
- **Docker Desktop** running
- (for the mobile app) **Flutter 3.24+**; (to run the backend outside Docker) **Python 3.11**

See `SETUP.md` for install details and machine-specific notes.

### 1. Everything via Docker (recommended)

```bash
cp backend/.env.example backend/.env     # copy .env.example .env on Windows
docker compose up -d --build             # postgres:5432  +  backend:8000
docker compose ps                        # both should be "healthy"
```

That's it — the backend container runs `alembic upgrade head` on start
(`AUTO_MIGRATE=1`), so a fresh clone comes up fully migrated with no extra step.
API keys can stay blank in dev (features degrade, logged at startup).

- API docs:   http://localhost:8000/docs
- Health:     `GET http://localhost:8000/health` → `{"status":"ok","db":"connected"}` (503 if the DB is unreachable)

Vector stack, when you need it (Phase 3+):
`docker compose -f infra/docker-compose.yml up -d`  → Milvus `:19530`, Attu UI `:8100`.

### 2. Backend without Docker (alternative)

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate                   # Windows  (source .venv/bin/activate elsewhere)
pip install -r requirements.txt
cp .env.example .env                      # POSTGRES_HOST stays "localhost" here
# start just Postgres:  docker compose up -d postgres
alembic upgrade head
uvicorn app.main:app --reload            # http://localhost:8000/docs
```

### 3. Mobile

```bash
cd mobile
flutter pub get
flutter run -d chrome                    # or: -d windows, or an Android/iOS device
```

The Home screen has a "Ping backend /health" button to confirm the app can reach
the API. On the Android emulator the API is reached at `http://10.0.2.2:8000`;
override with `--dart-define=API_BASE_URL=https://...` for other targets.

---

## Layout

```
backend/
  Dockerfile    python:3.11-slim image
  app/
    main.py       app + GET /health (DB readiness -> 200 or 503)
    api/          FastAPI routers          (api/v1/routes/*.py)
    models/       SQLAlchemy ORM models
    services/     business logic + integrations (OCR, openFDA, USDA, scoring, Claude)
    core/         config (composes DATABASE_URL from POSTGRES_* or uses an override), security
    db/           engine / session / declarative base
    vector/       Milvus client helper
  alembic/      migrations (env.py -> settings.sqlalchemy_url)

mobile/lib/src/
  core/         theme (CareCart design tokens), api client
  routing/      go_router config
  features/     one folder per screen group
```

## Secrets

All secrets live in `backend/.env`, which is **gitignored and never committed**.
Every teammate copies `backend/.env.example` (committed, blank values) to their
own `.env`. Never hardcode a key — even a placeholder — into source.

## Data prep

`gradient-ascend-mobile-app/project/dataset/data_prep/` holds a one-time offline
pipeline: food ingredients → risk compounds, medicine salts → drug classes, and a
**draft** food×drug interaction table (every row flagged `NEEDS CLINICAL REVIEW`).
See its `README.md` / `SUMMARY.md`.
