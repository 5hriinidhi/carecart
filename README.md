# CareCart

Scan a food label, get a verdict that's checked against **your** medications,
conditions, allergies, and profile-derived nutrient ceilings — not a generic score.

Monorepo:

| Path | What |
|---|---|
| `mobile/` | Flutter app (Riverpod + go_router), targets Android & iOS (web enabled for fast local iteration) |
| `backend/` | FastAPI service (Python 3.11, SQLAlchemy 2 + Alembic, PostgreSQL, Milvus) |
| `infra/` | `docker-compose.yml` — Postgres 15 + Milvus (+ Neo4j, Phase 6+) |
| `gradient-ascend-mobile-app/` | The approved UI design (`CareCart App.dc.html`) — reference, the app must match it |
| `SETUP.md` | One-time toolchain setup + what's already installed on this machine |

---

## Run it locally

### Prerequisites
- **Flutter 3.24+** and **Python 3.11** on `PATH`
- **Docker Desktop** running (for Postgres + Milvus)

See `SETUP.md` for install details and machine-specific notes.

### 1. Infrastructure

```bash
cd infra
docker compose up -d          # postgres:5432, milvus:19530, Attu UI :8000
docker compose ps             # wait for "healthy" (milvus ~90s)
```

### 2. Backend

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate                 # Windows  (source .venv/bin/activate elsewhere)
pip install -r requirements.txt

copy .env.example .env                  # then fill in DATABASE_URL + API keys
#   DATABASE_URL=postgresql+psycopg://carecart:carecart@localhost:5432/carecart

alembic upgrade head                     # apply migrations
uvicorn app.main:app --reload           # http://localhost:8000/docs
```

Health check: `GET http://localhost:8000/api/v1/health` → `{"status":"ok"}`
(and `/api/v1/health/db` once Postgres is up).

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
backend/app/
  api/          FastAPI routers          (api/v1/routes/*.py)
  models/       SQLAlchemy ORM models
  services/     business logic + integrations (OCR, openFDA, USDA, scoring, Claude)
  core/         config, security (JWT + bcrypt)
  db/           engine / session / declarative base
  vector/       Milvus client helper

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
