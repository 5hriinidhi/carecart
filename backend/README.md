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

### `POST /api/v1/products/scan-label` — ingredient-list OCR fallback (Phase 4.2)

For unbranded / regional products not in Open Food Facts. Multipart image →
`pytesseract` → the raw OCR text **plus** a best-effort parse into individual
ingredient strings:

- Splits on top-level `,` / `;` (bracketed sub-lists like `colour (caramel,
  E150d)` stay whole); strips a leading `Ingredients:` label, bullets and edge
  punctuation; drops fragments with no letters and packaging boilerplate
  (`May contain…`, URLs, `Best before…`); de-dupes.
- Returns `editable: true` **always** — the parse is a draft; the client must
  show the user an editable list (against `raw_text`) before it's used. Nothing
  is persisted.
- Also returns `ocr_confidence` (0–1) and, when the scan is unreliable — low
  mean word confidence **or** implausibly little text extracted (a rotated /
  dim / blurry photo where OCR salvaged one word), or nothing parseable —
  `low_confidence: true` with a plain-language `note` telling the user to check
  every line or retake. A bad photo never comes back as a silent empty result.
- Same upload guards as the medication scan: `415` non-image, `413` >10 MB,
  `422` unreadable image — all before OCR; `503` if tesseract is missing.

### `POST /api/v1/products/resolve-risks` — ingredient → risk_compound tags (Phase 4.3)

Takes a raw ingredient list (from a 4.1 barcode lookup or a 4.2 label scan) plus
optional per-100 g `nutriments`, and resolves each ingredient's `risk_compound`
tags **entirely from pre-built static tables in Postgres — no LLM, no network
call on this path, ever.**

Reference tables (loaded by `scripts/load_risk_tables.py` from
`dataset/data_prep/*.csv`):

| table | from | used for |
|---|---|---|
| `risk_compounds` | `risk_compounds.csv` | the 26 canonical categories |
| `ingredient_risk_aliases` | `ingredient_aliases.csv` (`source='keyword'`) + `llm_ingredient_tags.csv` (`source='llm'`, `match_type='exact'`; a NULL `risk_compound` row = a token reviewed as benign) | `alias → risk_compound` matching |
| `risk_nutrient_thresholds` | `risk_nutrient_thresholds.csv` | numeric per-100 g bands (FSA front-of-pack) → whole-product tags |
| `food_risk_tags` | `food_risk_tags.csv` | per-food precompute, loaded for 4.4 to reuse |

Matching (keyword substring/word + negation + coconut/bean suppression, then the
LLM-table exact pass, then a benign list) is a direct port of the one-time
data-prep tagger, so runtime tags line up with `food_risk_tags.csv`.

Response: `ingredients[]` (each with `method` = `keyword` | `llm` | `benign` |
`unverified`, `risk_compounds`, `confidence`), `product_tags[]` from the
threshold pass, `risk_compounds` (union → max confidence — **what 4.4 scores**),
and the unverified handling:

- An ingredient that matches nothing comes back `method: "unverified"` (empty
  `risk_compounds`) — never dropped, never treated as safe.
- `caution_factors` carries `"We couldn't confirm N ingredient(s) in this
  product."` whenever any ingredient is unverified — 4.4 must surface this as a
  visible caution.
- Each distinct unverified text is upserted into the `unresolved_ingredients`
  queue (`ingredient_text`, `normalized_text` unique, `first_seen_at`,
  `times_seen`, `sample_product`, `status`) — repeats bump `times_seen`, never a
  duplicate row. Set `RISK_QUEUE_UNRESOLVED=0` to skip the write (the marker is
  still returned).

**Offline batch job** (`scripts/classify_unresolved.py`, *not* part of the app —
run by hand / on a schedule):

```bash
python -m scripts.classify_unresolved classify --out review.csv   # curated map; --use-api adds a live Claude call for misses (needs CLAUDE_API_KEY)
#   ... a human sets accept = y / n per row ...
python -m scripts.classify_unresolved merge --reviewed review.csv  # accepted rows → llm_ingredient_tags.csv (+ audit line); queue rows → merged / rejected
(cd ../gradient-ascend-mobile-app/project/dataset/data_prep && python 03_tag_foods.py)
python -m scripts.load_risk_tables                                 # redeploy the reference tables
```

Classification carries `method` (`llm-curated` / `llm-api` / `unclassified`),
`confidence` (clamped ≤ 0.9), `model` and `rationale` — nothing is auto-trusted;
the merge step only takes rows a human marked `accept`.

### `POST /api/v1/scan/verdict` — food-drug interaction & severity scoring (Phase 4.4)

Takes a product's decoded `ingredients` (from 4.1 / 4.2) + per-100 g
`nutriments` and scores them against the **authenticated user's** stored
`conditions`, `allergies` and *active* `medications` (read server-side from the
JWT — the client never sends them). Returns a **0–100 `score`**, a **`tier`**
(`safe` ≥ 70, `caution` ≥ 45, else `avoid` — the exact `chipFor()` thresholds
from the Flutter theme), and a plain-language `reasons` list.

Model: **start at 100, subtract a deduction per matched risk factor** —

| factor | source | deduction |
|---|---|---|
| drug–food interaction | `interaction_rules` (drug_class × risk_compound), e.g. warfarin / vitamin K, lithium / sodium | HIGH −35 · MODERATE −20 · LOW −8 |
| condition nutrient ceiling exceeded | `condition_diet_rules` (`nutrient_ceiling`) vs `nutriments` | HIGH −28 · MOD −16 · LOW −8 (+10 if ≥ 2× the ceiling) |
| condition risk compound present | `condition_diet_rules` (`risk_compound`) | HIGH −28 · MOD −14 · LOW −7 |
| general poor-fit | high sugar / sodium / sat-fat / trans-fat / refined carb not tied to the user | −3 / −6 each, capped −18 |
| unverified ingredients (4.3) | `resolution.unverified` | −4 each, capped −12 |

An **allergen match is a hard stop**: any stored allergy (`allergen_aliases`
maps the free text → an allergen `risk_compound`) matching any ingredient forces
`score: 0`, `tier: "avoid"`, `hard_stop: true` — *regardless of the numeric
score*, matching the proposal's "allergens are a full-screen stop, not a
deduction." The allergen reason carries `points: 0`.

Medication names are mapped to a `drug_class`: `drug_name_aliases` (brand →
generic — "Ecosprin" → aspirin) **first**, then `drug_class_lookup`, then
`drug_class_stem_rules` (`-pril` → ACE inhibitor, `-floxacin` → Fluoroquinolone,
…). A name that still resolves to no class is reported (`identified: false`) and
not checked for interactions — never a silent pass. Reading the vault writes an
`audit_log` row (who / when / status, no content). Every `interaction_rules` row
is a clinician-review DRAFT, so wording stays "keep intake consistent" /
"caution", never medical advice.

**Precedence** when a product matches several rules at once:

1. **Allergen match wins outright** — `score 0`, `tier avoid`, `hard_stop`, no
   matter the arithmetic.
2. Otherwise **every other factor stacks additively**, de-duped first: a
   compound cited by a drug interaction or condition rule isn't *also* counted
   as general poor-fit, and two nutrient keys for one concern (`sodium_mg` +
   `salt_g`) count once. Score clamps to 0–100.
3. **HIGH-severity floor** — if any HIGH-severity drug interaction / condition
   ceiling / condition compound fired, the tier is at least `caution` even when
   the number lands ≥ 70 (a well-established clinical interaction never reads
   "Safe for you").
4. `reasons` come back most-serious-first: allergen → drug_interaction →
   condition_ceiling → condition_compound → poor_fit → unverified → clear.

### Timeouts & offline behaviour (Phase 4)

- **Open Food Facts**: `httpx` call bounded by `OFF_TIMEOUT_SECONDS` (8 s). On a
  timeout / error the route serves an expired cache entry (`X-Cache: STALE`) if
  it has one, else a `502` with the OCR-fallback hint — it never hangs.
- **`/scan/verdict`** makes no outbound calls (pure DB) — typ. < 120 ms.
- **Claude API** is *offline only* (the `classify_unresolved.py` batch job,
  30 s timeout, failure → "unclassified"). Never on the scan path.
- **Mobile**: `dioProvider` sets a 10 s connect / 15 s receive timeout, so the
  UI always resolves — a slow/rate-limited backend surfaces "The server is
  taking too long…", a dead one "No connection to the server."; the scan-screen
  banner shows the message instead of spinning.
- **What needs connectivity**: every scan (product lookup *and* verdict are
  server-side — the rule tables and the user's vault live on the backend). What
  degrades gracefully: OFF down but the product already cached → verdict still
  computed off the stale copy; backend down → a clear error on the scan screen,
  no partial/false verdict.

### Automatic diet log — `scan_history` + `GET /api/v1/history` (Phase 5.1)

**Every** completed `POST /scan/verdict` writes one `scan_history` row in the
same transaction as the verdict — no separate "log this" call, ever. A scan that
produced a verdict is by definition something the user considered, so it is
logged unconditionally (hard-stop verdicts included).

| column | notes |
|---|---|
| `user_id`, `score`, `tier`, `hard_stop`, `scanned_at` | plaintext — structural; Phase 5.2 trends aggregate on `score`/`tier`/`scanned_at` |
| `product_name`, `barcode`, `key_reasons` (`[{kind,severity,title}]`, top 4) | **Fernet-encrypted at rest**, like the rest of the vault — a scan history reveals health behaviour |
| `seq` (`BIGINT IDENTITY`) | monotonic insertion order — the authoritative "most recent first" key, so pagination is stable even when two scans share a `scanned_at` |

`GET /api/v1/history?limit=&offset=` (JWT required) → `{ items[], total, limit,
offset, has_more }`, ordered `seq DESC`, **scoped to the caller only**
(`WHERE user_id = current_user.id`). `limit` 1–100 (default 20), `offset` ≥ 0.
Rows cascade-delete with the account.

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
  models/__init__.py   auth + vault + Product + 4.3 risk tables + 4.4 InteractionRule / DrugClassLookup / DrugClassStemRule / ConditionDietRule / AllergenAlias / DrugNameAlias + ScanHistory (5.1 diet log) + AuditLog
  schemas/auth.py, schemas/vault.py   request/response models
  services/phone.py    E.164 normalisation
  services/otp.py      challenge lifecycle: rate-limit / issue / verify
  services/otp_sender.py  ConsoleOtpSender (dev) | HttpOtpSender (adapt to your provider)
  services/ocr.py      pytesseract wrapper: open_image / extract_text / sanitize_text / guess_medication
  services/ingredient_risk.py  offline ingredient → risk_compound resolver (static tables only, no LLM)
  services/verdict.py  Phase 4.4 scoring: deductions → 0-100 score + tier; allergen hard-stop
  scripts/load_risk_tables.py     deploy step: load dataset/data_prep/*.csv → Postgres reference tables
  scripts/classify_unresolved.py  offline batch job: drain unresolved_ingredients → review CSV → merge
  api/deps.py          DbSession, get_current_user / CurrentUser
  api/v1/router.py      aggregate v1 router  (add feature routers here)
  api/v1/routes/        endpoint modules (health.py, auth.py, products.py, scan.py, history.py, vault.py)
  vector/milvus_client.py   lazy MilvusClient helper
```

## Next

- Phase 4.5+: persist a `ScanHistory` row per verdict; surface the reasons on the
  Flutter result screen.
- Get `interaction_rules.csv` clinician-reviewed (every row is currently a DRAFT)
  and widen `condition_diet_rules.csv` / brand-name → generic drug mapping.

## Lint / test

```bash
ruff check app
ruff format app
pytest
```
