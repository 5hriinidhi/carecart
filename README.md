# CareCart

Scan a food label — get a verdict scored 0–100 and checked against **your**
medications, conditions, allergies, profile-derived nutrient ceilings, **and**
your lifestyle. Not a generic score.

Everything runs on-device / table-lookup: no live LLM on the scan path, no
analytics or crash SDK, health data is encrypted at rest and deletable in one
tap.

Monorepo:

| Path | What |
|---|---|
| `mobile/` | Flutter app (Riverpod + go_router), Android & iOS |
| `backend/` | FastAPI (Python 3.11, SQLAlchemy 2 + Alembic, PostgreSQL 15) + `Dockerfile` |
| `docker-compose.yml` | Postgres + backend, auto-migrated on start |
| `gradient-ascend-mobile-app/` | the approved UI design + the raw reference datasets |
| `DEMO.md` | full runbook: seeded personas, release build, phone install |
| `SETUP.md` | one-time toolchain setup |

---

## What's in the app

- **Sign in** with a phone number + OTP. In dev the backend echoes the code, so
  no SMS provider is needed. *(Google sign-in is scaffolded but not wired yet.)*
- **Onboarding** — name, then 7 steps: sex, activity (days/week), body, diet,
  allergies, medications, and a lifestyle step (sleep / smoking / alcohol / stress).
- **Barcode scan** → live Open Food Facts lookup → a personalised verdict.
  Unknown barcodes say so; they never return a wrong product.
- **CareCart Fit** — a lifestyle + medicines correlation score (`GET /me/fit`):
  an overall number, a Lifestyle section and a Medicines section, all
  deterministic arithmetic (`backend/app/services/fit.py`).
- **Verdict tie-in** — a poor lifestyle dimension amplifies the matching
  nutrition deduction (e.g. high stress ×1.25 on added sugar); the applied
  multipliers are shown on the result.
- **Medicines** — add/remove from a searchable catalogue of ~7.5k Indian brand
  names, each change gated by an on-device PIN.
- **Look it up** — search ~1,100 everyday foods (home dishes + packaged
  products) without a barcode.
- **Full profile page**, **History**, **Trends**, **Nudges**.

---

## Run the backend

```bash
cp backend/.env.example backend/.env      # copy backend\.env.example on Windows
docker compose up -d --build              # postgres + backend, auto-migrated
docker compose ps                         # both should be "healthy"
```

- Health:  `GET http://localhost:8000/health` → `{"status":"ok","db":"connected"}`
- Docs:    http://localhost:8000/docs  (dev only)

Load the reference data (once, and whenever the CSVs change):

```bash
docker compose exec backend python -m scripts.load_risk_tables
docker compose exec backend python -m scripts.load_drug_catalog
docker compose exec backend python -m scripts.load_food_catalog
# optional demo fixtures:
docker compose exec backend python -m scripts.seed_demo_products
docker compose exec backend python -m scripts.seed_demo_users --reset
```

Backend without Docker: `cd backend && python -m venv .venv && .venv\Scripts\activate
&& pip install -r requirements.txt`, start just Postgres
(`docker compose up -d postgres`, publishes host port 5433), set
`POSTGRES_HOST=localhost` / `POSTGRES_PORT=5433` in `.env`, then
`alembic upgrade head && uvicorn app.main:app --reload`.

## Run the app

```bash
cd mobile
flutter pub get
flutter run                               # a connected Android/iOS device
```

Point it at the backend with `--dart-define=API_BASE_URL=http://<host>:8000`
(`10.0.2.2:8000` from an Android emulator).

### On a physical phone (short version)

1. One-time: JDK 17 or 21 (`flutter config --jdk-dir="…"`); phone with USB
   debugging on.
2. Run the backend bound to `0.0.0.0:8000` on your laptop, open port 8000, and
   confirm `http://<laptop-wifi-ip>:8000/health` loads from the phone's browser.
3. `cd mobile && .\tool\build_demo.ps1 -ApiBaseUrl http://<laptop-wifi-ip>:8000`
   then `flutter install --release`.
4. In the app: enter a 10-digit number starting 6–9 → the code auto-fills → do
   onboarding → scan something. Keep the backend terminal running.

Full detail (personas, ngrok, troubleshooting): **`DEMO.md`**.

---

## Tests

```bash
# backend  (needs Postgres; docker compose up -d postgres, then POSTGRES_PORT=5433)
cd backend && python -m pytest -q

# mobile
cd mobile && flutter analyze && flutter test
```

CI (`.github/workflows/ci.yml`) runs both plus an on-emulator integration test
against a real backend.

## Secrets & privacy

All secrets live in `backend/.env` (gitignored; copy the blank
`backend/.env.example`). Onboarding + scan data is health data: no telemetry
SDKs, no raw `print` in `lib/`, PII never leaves the device without the user
saying so — enforced by `mobile/test/no_pii_telemetry_test.dart` and
`backend/tests/test_no_internal_endpoints.py`. `ENVIRONMENT=production` refuses
to boot on placeholder secrets and stops echoing the OTP.
