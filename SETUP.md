# CareCart — dev environment setup

Stack from the proposal: **Flutter** (mobile) · **FastAPI + PostgreSQL + Alembic** (backend) ·
**Milvus** (vectors, via Docker) · **Neo4j** (graph, Phase 6+).

---

## ✅ Already done for you

| Area | State |
|---|---|
| **Python 3.11.4** | already installed |
| **Backend venv + all deps** | `backend/.venv/` created, `requirements.txt` installed (FastAPI, SQLAlchemy 2, Alembic, psycopg 3, pymilvus, PyJWT, bcrypt, ruff, pytest) |
| **Backend app skeleton** | `backend/app/…` — config, DB session, `User/Profile/Medication/ScanHistory` models, JWT+bcrypt helpers. `GET /health` does a real `SELECT 1` and returns `{"status":"ok","db":"connected"}` or **503** with the reason. Boots clean, lint clean, 3 pytest pass. |
| **backend/Dockerfile** | `python:3.11-slim`, installs `requirements.txt`, runs uvicorn on 8000. `.dockerignore` excludes `.venv`/`.env`. |
| **Alembic** | initialised, `env.py` → `settings.sqlalchemy_url` (same URL the app uses). No migration generated yet — needs a running Postgres. |
| **Flutter 3.38.5 / Dart 3.10.4** | already installed at `C:\flutter` |
| **Flutter app** | `mobile/` created (`com.carecart`, platforms android/ios/web). Added **flutter_riverpod 3.x**, **go_router 17**, **dio**, **flutter_secure_storage**. Scaffolded theme (CareCart design tokens), `dioProvider`, go_router with an onboarding→app redirect, placeholder Onboarding/Home screens. `flutter analyze` + `flutter test` pass. |
| **Docker Compose** | root `docker-compose.yml` = **postgres:15 + backend** (postgres reads creds from `backend/.env`, has a healthcheck, backend `depends_on` it; named `pgdata` volume). `infra/docker-compose.yml` = Milvus stack (same compose project). Both validated. |
| **.gitignore** | updated for `backend/.venv`, `mobile/build`, `.env`, etc. |

---

## 🔧 What you need to do

### 1. Start Docker Desktop  (required for Postgres + backend)
Docker CLI is installed but the engine isn't running.

```powershell
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
# wait ~1 min for the whale icon to go steady
```

### 2. Backend: create `.env`, bring up the stack, run migrations

```powershell
cd C:\Users\Shrinidhi\CARECART
copy backend\.env.example backend\.env
# (POSTGRES_* dev creds in .env are fine as-is; fill API keys when you have them)

docker compose up -d --build                          # postgres + backend, auto-migrated
docker compose ps                                     # both "healthy" (~25s from cold on a warm image)
```
The initial migration is committed and the container auto-applies it on start,
so no `alembic` command is needed for a fresh setup. Check
http://localhost:8000/docs and http://localhost:8000/health → `{"status":"ok","db":"connected"}`.

Later, to add a migration after changing models:
`docker compose exec backend alembic revision --autogenerate -m "..."` then restart the backend.

Vector stack (Milvus), only from Phase 3 on:
`docker compose -f infra\docker-compose.yml up -d`  → Milvus `:19530`, Attu UI http://localhost:8100

### 3. Flutter: accept Android licenses (only for Android builds)

```powershell
flutter doctor --android-licenses      # press y at every prompt
```
You can skip this for now — **the app already runs on web and Windows**:

```powershell
cd C:\Users\Shrinidhi\CARECART\mobile
flutter run -d chrome
# tap "Skip onboarding" -> Home -> "Ping backend /health"  (start the backend first)
```

### 4. Android builds: fix the JDK  (only when you build for Android)
You have **JDK 26**; the Android Gradle Plugin needs **17 ≤ JDK < 25**.
Android Studio ships a compatible JDK — point Flutter at it:

```powershell
winget install --id Google.AndroidStudio -e        # if not already installed
flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"
flutter doctor -v                                   # Android toolchain should go green
```
(Or `winget install --id EclipseAdoptium.Temurin.17.JDK` and point `--jdk-dir` there.)

### 5. Node.js — not needed
The stack is Flutter + Python. Skip unless a future tool requires it
(`winget install OpenJS.NodeJS.LTS`).

---

### Common snags (per-machine)

- **Port already in use** (local Postgres on 5432, another API on 8000): defaults
  are already Postgres `5433` / backend `8000`; override with
  `POSTGRES_HOST_PORT` / `BACKEND_HOST_PORT` (repo-root `.env`, see `/.env.example`).
- **Compose v1**: `docker-compose` (hyphen) can't parse this repo. Use Docker
  Desktop's bundled Compose v2 (`docker compose`, space).
- **Flutter/Dart drift between teammates**: pinned in `/.tool-versions` (asdf/mise)
  and `/mobile/.fvmrc` (fvm); floor in `mobile/pubspec.yaml`. `sh scripts/check-env.sh`
  reports mismatches.
- **Line endings**: `.gitattributes` forces `*.sh` (incl. `backend/entrypoint.sh`)
  to LF so the Linux container can run them. If a script fails with
  `bad interpreter` / `\r`, run `git add --renormalize . && git checkout -- .`.

---

### 6. Later / optional
- **Neo4j** (Phase 6+): uncomment the `neo4j` service in `infra/docker-compose.yml` and the `neo4j` line in `backend/requirements.txt`.
- **Pinecone** instead of Milvus: swap `pymilvus` for `pinecone-client` in `requirements.txt`, set an API key in `.env`. Only if you outgrow local Milvus.
- **Riverpod codegen** (`@riverpod` + `riverpod_generator`/`riverpod_lint`): skipped — its versions don't currently resolve against Dart 3.10 + Riverpod 3.x. The hand-written provider API works fine; revisit when the lint package catches up.
- **Fonts**: drop `BricolageGrotesque` + `DMSans` `.ttf` into `mobile/assets/fonts/`, declare them in `pubspec.yaml`, and `theme.dart` will pick them up.

---

## Repo layout after this

```
CARECART/
├─ backend/                 FastAPI service  (see backend/README.md)
│  ├─ app/                   application code
│  ├─ alembic/               migrations
│  ├─ requirements.txt
│  └─ .env.example
├─ mobile/                  Flutter app
│  └─ lib/src/               theme / routing / features
├─ infra/
│  └─ docker-compose.yml     postgres + milvus (+ neo4j, commented)
├─ gradient-ascend-mobile-app/   the Claude Design prototype (reference)
└─ SETUP.md                 this file
```

Nothing here has been committed yet — review, then `git add` / `git commit` / `git push`.
