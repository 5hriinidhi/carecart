# CareCart backend (FastAPI)

## Stack
FastAPI 0.115 · SQLAlchemy 2.0 · Alembic · psycopg 3 · PostgreSQL 15 · pymilvus 2.5 · PyJWT · bcrypt · cryptography (Fernet) · pytesseract + Pillow

## Run with Docker (recommended)

```bash
cp .env.example .env                              # from repo root: copy backend\.env.example backend\.env
docker compose up -d --build                      # runs from repo root; postgres + backend
```

The image's `entrypoint.sh` runs `alembic upgrade head` before starting uvicorn
(disable with `AUTO_MIGRATE=0`), so `up` alone gives a migrated DB.

- API docs: http://localhost:8000/docs
- Health:   http://localhost:8000/health → `{"status":"ok","db":"connected"}` (503 + reason if the DB is down)

## Auth (phone + OTP)

Matches the onboarding UI's `login → otp` steps.

| Method | Path | Notes |
|---|---|---|
| `POST` | `/api/v1/auth/request-otp` | `{phone}` → sends a 6-digit code (5-min expiry). Rate-limited to 3 per phone per 10 min (`429` + `Retry-After`). In dev the code comes back as `dev_code` (no SMS provider needed); it is **never logged**. |
| `POST` | `/api/v1/auth/verify-otp` | `{phone, code}` → `{access_token, refresh_token, token_type, expires_in, is_new_user}`. Creates the user on first success. Wrong/expired/too-many-attempts all return the same generic `400`. |
| `POST` | `/api/v1/auth/refresh` | `{refresh_token}` → rotated pair; the old refresh token is revoked. |
| `POST` | `/api/v1/auth/logout` | `{refresh_token}` → `204`, token revoked. |

Access token: 30 min, JWT (`typ=access`, `jti`). Refresh token: 30 days, opaque,
stored as a SHA-256 hash, single-use (rotated). Set `OTP_PROVIDER_URL` +
`OTP_PROVIDER_API_KEY` to send real SMS via `HttpOtpSender` (adapt the payload
to your provider in `app/services/otp_sender.py`).

## Products (barcode lookup)

`GET /api/v1/products/{barcode}` (JWT required) — looks a barcode up via the
Open Food Facts API and caches the result in the `products` table for
`PRODUCT_CACHE_TTL_HOURS` (24h, to stay within OFF's rate limits).

- **Hit** → `200` with a normalised product: `name`, `brand`, `ingredients`
  (list) + `ingredients_text`, `nutriments` per 100 g (`sugars_g_100g`,
  `sodium_mg_100g` — OFF's grams converted to mg, etc.), `serving_size`,
  `image_url`. `cached` / `stale` flags say where it came from.
- **Miss** → `404` `{"detail": "...", "barcode": "...", "fallback": "ocr"}` so
  the client falls back to scanning the ingredients list. Misses are cached too.
- Barcode must be 8–14 digits (`422` otherwise). If OFF is unreachable an
  expired cache entry is served with `stale: true`; with no cache at all → `502`
  (bounded by `OFF_TIMEOUT_SECONDS`, never hangs).
- Every response carries an **`X-Cache`** header: `MISS` (fetched from OFF just
  now), `HIT` (served from Postgres, no OFF call), or `STALE` (OFF was down, an
  expired copy was served).
- OFF etiquette: every request sends a descriptive `User-Agent`
  (`OFF_USER_AGENT`), and the cache means a repeat scan never touches OFF.

## Health Identity Vault

Every table is keyed to `users.id`. `users` stores only `phone_hash` — a keyed
HMAC of the E.164 number (`PHONE_HASH_KEY` pepper), never the plaintext.

| Table | Endpoints (`/api/v1`) | Encrypted at rest |
|---|---|---|
| `health_profiles` (1:1) | `GET / PUT / PATCH / DELETE /me/health-profile` | — |
| `conditions` | `GET / POST /me/conditions`, `GET / PATCH / DELETE /me/conditions/{id}` | `condition_name` |
| `allergies` | `GET / POST /me/allergies`, `GET / PATCH / DELETE /me/allergies/{id}` | — |
| `medications` | `GET / POST /me/medications`, `GET / PATCH / DELETE /me/medications/{id}` | `name`, `dosage` |

### `POST /api/v1/me/medications/scan` — label OCR (Phase 3.3)

Multipart image upload of a medication label → Tesseract OCR → a **guess**
(`name_candidate` + `name_confidence` 0-1, `dosage_candidate`, sanitised
`raw_text`). It **never saves** — `confirmation_required` is always `true`; the
client shows the guess, the user confirms/edits, then saves via
`POST /me/medications`.

- Rejected **before OCR**: non-image `Content-Type` → `415`; body over
  `OCR_MAX_UPLOAD_BYTES` (10 MB) → `413`; empty / non-decodable image → `422`.
- Extracted text is sanitised before it's returned or parsed: control /
  format characters stripped, whitespace collapsed, length capped at
  `OCR_TEXT_MAX_CHARS` (4000, then `raw_text_truncated: true`).
- The guess is a deterministic heuristic over the OCR output — no model call.
- Needs the `tesseract` binary (in the Docker image; set `TESSERACT_CMD` if it's
  not on `PATH` locally). Missing binary → `503`.

- **Every endpoint requires a valid access token** and is scoped to that user:
  lists filter `user_id = current_user.id`; single rows match `(id, user_id)`
  together, so a foreign or unknown id is a 404 — one user can never see or
  change another's rows.
- `DELETE /api/v1/me/account` — **hard delete** of the account. Removes the
  `users` row; Postgres `ON DELETE CASCADE` takes `health_profiles`,
  `conditions`, `allergies`, `medications` and `refresh_tokens` with it. No soft
  flag, not reversible; the access/refresh tokens stop working immediately.

Edge-case hardening (Phase 3):

- `verify-otp` get-or-create is race-safe — `INSERT ... ON CONFLICT (phone_hash)
  DO NOTHING RETURNING id`, so the same number registering twice never makes a
  second account or a 500.
- `PUT /me/health-profile` is an atomic `ON CONFLICT (user_id) DO UPDATE` upsert
  — two devices submitting the profile at once converge to one row (last write
  wins), never a 500.
- Server-side length limits: `condition_name`/`medication.name`/`dosage` ≤ 200,
  `allergen_name` ≤ 120, `body_metrics` is a fixed 4-field shape (`extra=forbid`,
  bounded numbers), `diet_type` ≤ 40 tags of ≤ 60 chars. Over-long input → 422.
- OTP: a provider transport error **or** a `2xx` response whose body signals
  failure both surface as `502` (never a silent "sent"), and don't persist a
  challenge / consume a rate-limit slot.
- OCR: if nothing on the image looks like a drug label (no dosage, no
  `tablet`/`mg`/… context) the name-guess confidence is halved, so a non-label
  photo can't produce a confident wrong answer.
- **App-layer encryption** (`app/core/crypto.py` + `app/db/types.py`):
  **every PHI column** is Fernet-encrypted before it hits Postgres — condition
  names, allergen names, medication name/dosage, and the health-profile fields
  (`gender`, `activity_level`, `body_metrics`, `diet_type`). Only structural
  columns (ids, `user_id`, timestamps) are plaintext. `users` stores a keyed
  HMAC, never the phone number. Keys load from settings (`ENCRYPTION_KEY` +
  `ENCRYPTION_KEYS_OLD` for `MultiFernet` rotation), never from source. Encrypted
  columns can only be filtered by `user_id`, never by their own value.

### Compliance foundation (DPDP / HIPAA-style)

- **Ownership on every endpoint.** Every `/me/*` route requires a valid JWT and
  scopes to that user; id lookups match `(id, user_id)` so a foreign id is a
  404. `tests/test_phase3_security.py` auto-discovers all `/me/*` routes and
  asserts each rejects missing / garbage tokens — the check can't fall behind a
  new endpoint.
- **Audit log** (`audit_log`, append-only): who (`user_id`), verb
  (`read`/`write`/`delete`), resource kind, row id, response status, timestamp.
  It holds **no health-data content** — the table has exactly those columns and
  nothing else. Written in the same transaction as the operation it records.
- **No internal leakage.** `debug` is forced off when `ENVIRONMENT=production`,
  and a catch-all handler turns any uncaught error into
  `500 {"detail": "Internal server error"}` (the real error is logged
  server-side only) — no traceback, SQL, or row data reaches the client.
- **Deletion is complete.** `DELETE /me/account` hard-deletes the `users` row;
  `ON DELETE CASCADE` removes `health_profiles`, `conditions`, `allergies`,
  `medications`, `refresh_tokens` **and `audit_log`** — verified by raw
  `SELECT count(*) = 0` across every table. No soft-delete flag.

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
  core/security.py     bcrypt (password/OTP) + JWT access tokens + opaque refresh tokens + hash_phone + mask_phone
  core/crypto.py       Fernet encrypt/decrypt (MultiFernet, keys from settings)
  db/base.py           DeclarativeBase + TimestampMixin
  db/types.py          EncryptedString column type (transparent at-rest encryption)
  db/session.py        engine + SessionLocal + get_db dependency
  models/__init__.py   User, OtpChallenge, RefreshToken, HealthProfile, Condition, Allergy, Medication, ScanHistory
  schemas/auth.py, schemas/vault.py   request/response models
  services/phone.py    E.164 normalisation
  services/otp.py      challenge lifecycle: rate-limit / issue / verify
  services/otp_sender.py  ConsoleOtpSender (dev) | HttpOtpSender (adapt to your provider)
  services/ocr.py      pytesseract wrapper: open_image / extract_text / sanitize_text / guess_medication
  api/deps.py          DbSession, get_current_user / CurrentUser
  api/v1/router.py      aggregate v1 router  (add feature routers here)
  api/v1/routes/        endpoint modules (health.py, auth.py, vault.py)
  vector/milvus_client.py   lazy MilvusClient helper
```

## Next

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
