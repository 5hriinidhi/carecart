# CareCart — dev environment setup

Stack from the proposal: **Flutter** (mobile) · **FastAPI + PostgreSQL + Alembic** (backend) ·
**Milvus** (vectors, via Docker) · **Neo4j** (graph, Phase 6+).

---

## ✅ Already done for you

| Area | State |
|---|---|
| **Python 3.11.4** | already installed |
| **Backend venv + all deps** | `backend/.venv/` created, `requirements.txt` installed (FastAPI, SQLAlchemy 2, Alembic, psycopg 3, pymilvus, PyJWT, bcrypt, ruff, pytest) |
| **Backend app skeleton** | `backend/app/…` — config, DB session, `User/Profile/Medication/ScanHistory` models, JWT+bcrypt helpers, `/api/v1/health` + `/health/db`. Boots clean, lint clean. |
| **Alembic** | initialised, `env.py` wired to app settings + model metadata (no migration generated yet — needs a running Postgres) |
| **Flutter 3.38.5 / Dart 3.10.4** | already installed at `C:\flutter` |
| **Flutter app** | `mobile/` created (`com.carecart`, platforms android/ios/web). Added **flutter_riverpod 3.x**, **go_router 17**, **dio**, **flutter_secure_storage**. Scaffolded theme (CareCart design tokens), `dioProvider`, go_router with an onboarding→app redirect, placeholder Onboarding/Home screens. `flutter analyze` + `flutter test` pass. |
| **Docker Compose** | `infra/docker-compose.yml` for Postgres 15 + Milvus (+ etcd/minio + Attu UI). Neo4j block included, commented. Validated. |
| **.gitignore** | updated for `backend/.venv`, `mobile/build`, `.env`, etc. |

---

## 🔧 What you need to do

### 1. Start Docker Desktop  (required for Postgres + Milvus)
Docker CLI is installed but the engine isn't running.

```powershell
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
# wait ~1 min for the whale icon to go steady, then:
cd C:\Users\Shrinidhi\CARECART\infra
docker compose up -d
docker compose ps            # postgres + milvus should be "healthy" (milvus takes ~90s)
```
Milvus web UI: http://localhost:8000  ·  Postgres: `localhost:5432` user/pass/db all `carecart`.

### 2. Backend: create `.env` and run the first migration

```powershell
cd C:\Users\Shrinidhi\CARECART\backend
copy .env.example .env
# generate a real JWT secret and paste it into .env:
python -c "import secrets; print(secrets.token_urlsafe(48))"

.\.venv\Scripts\activate
alembic revision --autogenerate -m "initial schema"   # needs Postgres up (step 1)
alembic upgrade head
uvicorn app.main:app --reload
```
Check http://localhost:8000/docs and http://localhost:8000/api/v1/health/db → `{"database":"reachable"}`.

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
