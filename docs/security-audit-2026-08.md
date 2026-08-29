# Security & Data Privacy Audit — Phase 6.2

**Date:** 2026-08-30 · **Scope:** full codebase, 34-commit git history, Python + Dart/Flutter dependency trees · **Method:** read-only review (one throwaway DB row created and deleted to verify cascade/encryption).

**Result:** 4 of 5 checklist items pass clean. Action items: a Python dependency refresh (2 HIGH), and a Postgres least-privilege gap (F1).

---

## 1. Endpoint auth + row-level ownership — PASS

Every endpoint that reads or writes user data takes `user: CurrentUser`
(`app/api/deps.py::get_current_user` → 401 on missing / undecodable / unknown /
inactive token) **and** scopes every query by `user_id`.

| Endpoint | JWT | Ownership scoping | Test |
|---|---|---|---|
| `GET /api/v1/analytics/trends` | ✔ | `WHERE ScanHistory.user_id == user.id` | `test_analytics_trends.py::test_requires_auth` |
| `GET /api/v1/history` | ✔ | `WHERE ScanHistory.user_id == user.id` (count + rows) | `test_scan_history.py::test_history_requires_auth`, `::test_history_is_scoped_to_the_caller` |
| `GET /api/v1/nudges` | ✔ | `WHERE Nudge.user_id == user.id` | `test_nudges.py` (401 ×2), `::test_nudges_are_scoped_per_user` |
| `POST /api/v1/nudges/{id}/dismiss` | ✔ | `WHERE id == … AND user_id == user.id` → 404 if not owned | ″ |
| `POST /api/v1/scan/verdict` | ✔ | reads `Condition/Allergy/Medication WHERE user_id == user.id`; writes `ScanHistory(user_id=user.id)` | `test_verdict.py::test_endpoint_requires_auth` |
| `POST /api/v1/products/scan-label` | ✔ | persists nothing user-linked | `test_scan_label.py` (401) |
| `POST /api/v1/products/resolve-risks` | ✔ | persists nothing user-linked | `test_ingredient_risk.py::test_resolve_risks_requires_auth` |
| `GET /api/v1/products/{barcode}` | ✔ | shared OFF cache, not user-scoped | `test_products.py` (401) |
| `/api/v1/me/*` — vault CRUD, health-profile (1:1), `DELETE /me/account` (16 routes) | ✔ | `_owned_or_404((id, user_id))` / `_my_profile(user_id)` / `user_id=user.id` on create | `test_phase3_security.py` auto-discovers **every** `/me/` route and parametrizes missing-token + garbage-token → 401, plus cross-user 404 |

**Unauthenticated by design** (no user data): `GET /health`, `GET /health/db`
(liveness); `POST /auth/{request-otp,verify-otp,refresh,logout}` (these mint /
rotate tokens; `refresh` and `logout` validate the refresh-token value itself).

Unhandled exceptions return a generic `{"detail":"Internal server error"}` with
the detail logged server-side only — no stack trace, SQL, or row data reaches
the client (`app/main.py::_unhandled_exception`).

## 2. Secrets in committed files & full git history — PASS (1 LOW finding)

- `.gitignore`: `.env`, `.env.*` (`!.env.example`), `.venv/`,
  `mobile/android/key.properties`. Only `*.env.example` is tracked; all secret
  values blank (the one non-blank value, `POSTGRES_PASSWORD=carecart`, is a
  documented dev-only local Postgres password).
- **Full-history scan** (`git log --all -p`, ~58k lines, 34 commits) for the two
  real keys, `sk-ant-*`, `AKIA*`, `AIza*`, `xox[baprs]-*`, `ghp_*`,
  `-----BEGIN … PRIVATE KEY-----`, and `secret|api_key|token|password = <20+ char>`:
  **zero matches** other than labelled dev placeholders.
- `backend/.env` exists locally, confirmed gitignored (`git check-ignore`), never
  tracked. No `google-services.json` / keystore / `key.properties` in `mobile/`.

**F3 (LOW):** `app/core/config.py` hardcodes real, usable dev fallbacks —
`_DEV_ENCRYPTION_KEY` (a valid Fernet key), `_DEV_JWT_SECRET`,
`_DEV_PHONE_HASH_KEY`. `missing_required()` refuses to boot only when
`environment.strip().lower() == "production"` **exactly**. A deploy with
`ENVIRONMENT` set to `prod` / `staging` / unset silently uses the committed keys
→ "encrypted at rest" data becomes decryptable by anyone with repo read access,
and phone-hash HMAC becomes rainbow-table-able.
*Fix:* fail closed unless the env-supplied keys are explicitly non-placeholder,
independent of `ENVIRONMENT`.

## 3. Dependency vulnerability scan

**Dart / Flutter** (`mobile/pubspec.lock`, 115 packages, OSV `Pub` ecosystem):
**no known advisories.**

**Python** (`pip-audit -r backend/requirements.txt`): 6 packages flagged.

| Package | Current | Fix to | Relevance | Severity |
|---|---|---|---|---|
| **PyJWT** | 2.10.1 | **≥ 2.13.0** | CVE-2026-32597 (CVSS 7.5, integrity), CVE-2026-48522–48526. This library **is** the auth model. | **HIGH** |
| **Pillow** | 11.0.0 | **≥ 12.3.0** | CVE-2026-54059 / -55379 / -55380 (CVSS 7.5, remote DoS via crafted image). Every `/me/medications/scan` + `/products/scan-label` upload is decoded by Pillow. | **HIGH** |
| **starlette** | 0.41.3 | ≥ 0.49.1 (via FastAPI bump) | CVE-2026-48710 "BadHost" (Host-header poisoning bypasses path-based checks — mitigated here: auth is dependency-based, not path rules), CVE-2025-62727. FastAPI 0.115.6 caps starlette `<0.42`. | HIGH class / low practical impact |
| **python-multipart** | 0.0.20 | ≥ 0.0.31 | CVE-2026-53539/53540/42561 malformed-multipart DoS. CVE-2026-24486 file-write needs non-default disk config → not exploitable as FastAPI uses it. | MEDIUM |
| **cryptography** | 44.0.0 | ≥ 44.0.1 (ideally 46.x) | CVE-2024-12797 (bundled OpenSSL) + newer. Backs Fernet-at-rest. | MEDIUM |
| **pytest** | 8.3.4 | ≥ 9.0.3 | CVE-2025-71176 — **dev-only, not shipped**. | LOW |

**Suggested `requirements.txt` bump** (then re-run `pytest` + `ruff` + `alembic check`):
`pyjwt==2.13.0`, `Pillow==12.3.0`, `python-multipart==0.0.31`,
`cryptography==44.0.1`, `fastapi==0.118.0` (pulls a patched starlette),
`pytest==9.0.3`.

## 4. Account-deletion cascade — PASS

`DELETE /api/v1/me/account` = `DELETE FROM users WHERE id = ?`, relying on
DB-level `ON DELETE CASCADE`. Verified against the **live migrated schema**
(`information_schema.referential_constraints`) — all 8 FKs to `users.id` cascade:

```
allergies        CASCADE      medications      CASCADE
audit_log        CASCADE      nudges           CASCADE
conditions       CASCADE      refresh_tokens   CASCADE
health_profiles  CASCADE      scan_history     CASCADE
```

Proven live: user + condition + medication → `DELETE FROM users` →
`conditions` / `medications` rows = 0. `test_phase6_e2e.py` asserts the same for
all 8 tables via raw SQL; `test_phase3_security.py` asserts the audit trail is
also removed. No soft-delete flag anywhere. Tables without a `user_id`
(`products`, `otp_challenges`, all reference/catalog tables) carry no PII.

**F5 (INFO):** no schema-introspection test to catch a future `user_id` table
added without `ON DELETE CASCADE`.

## 5. Encryption at rest — PASS

`app/db/types.py::EncryptedString` / `EncryptedJSON` (Fernet, application layer,
stored as `TEXT` tokens) cover every PHI column:

| Table | Encrypted columns |
|---|---|
| `health_profiles` | `gender`, `activity_level`, `body_metrics`, `diet_type` |
| `conditions` | `condition_name` |
| `allergies` | `allergen_name` |
| `medications` | `name`, `dosage` |
| `scan_history` | `product_name`, `barcode`, `key_reasons` |
| `nudges` | `message` |

Proven live — raw stored bytes are Fernet ciphertext (`gAAAAA…`), ORM read
decrypts transparently. Plaintext-by-design (needed for scoping / aggregation):
`user_id`, `id`, `seq`, `score`, `tier`, `hard_stop`, `scanned_at`, `factor`,
timestamps. `users.phone_hash` is a keyed HMAC (no plaintext phone numbers
stored). Asserted by `test_phase3_security.py`, `test_vault.py`,
`test_scan_history.py` — 76 tests green.

**Mobile privacy:** no analytics / crash-reporting SDK, no raw `print` /
`debugPrint` in `lib/`, no Dio payload-logging interceptor —
`mobile/test/no_pii_telemetry_test.dart` (3 tests) enforces this. Phone number +
OTP travel in POST bodies, never URL query strings.

---

## Cross-cutting findings

| # | Severity | Finding | Suggested fix |
|---|---|---|---|
| **F1** | **MEDIUM** | App connects to Postgres as a **superuser**. Live: role `carecart` has `rolsuper=t, rolcreatedb=t, rolcreaterole=t`, can `CREATE/DROP TABLE`. Phase 3's "dedicated low-privilege (DML-only) role, not the superuser" is not implemented — no separate role, no `GRANT` migration, no `.env.example` guidance. | Add a `carecart_app` role with `GRANT SELECT/INSERT/UPDATE/DELETE` on the app tables only; run migrations as the owner. Document both DSNs. |
| **F2** | LOW–MED | CORS default is `allow_origins=["*"]` + `allow_credentials=True`, with no production guard forcing `CORS_ORIGINS` to be set (unlike `JWT_SECRET`). | Add `CORS_ORIGINS` to the `is_production` checks in `missing_required()`. |
| **F3** | LOW | Committed dev fallback keys guarded only by exact `ENVIRONMENT=="production"` (§2). | Fail closed on placeholder keys regardless of `ENVIRONMENT`. |
| **F4** | LOW | `otp_challenges.phone_e164` stored plaintext (transient; bcrypt on the code; rows swept < 1 day). | Acceptable given TTL; optionally hash it too. |
| **F5** | INFO | No guard that a future `user_id` table gets `ON DELETE CASCADE` (§4). | Add an `information_schema` introspection test. |
