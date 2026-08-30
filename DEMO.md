# CareCart — demo / judging runbook (Phase 6.4)

A seeded demo backend + a release build of the app so trends, history and nudges
have realistic data the moment the app opens.

## 1. Bring up the demo backend

```bash
cd backend
cp .env.example .env                 # dev placeholders are fine for a demo
# ENVIRONMENT stays "development" on purpose — the backend then echoes the OTP
# in the POST /auth/request-otp response so judges can sign in without SMS.

# schema + reference data + demo fixtures
alembic upgrade head
python -m scripts.load_risk_tables
python -m scripts.seed_demo_products          # so live re-scans work
python -m scripts.seed_demo_users --reset     # the 4 personas + 4 weeks of history

uvicorn app.main:app --host 0.0.0.0 --port 8000
```

`docker compose up -d postgres` first if you don't have a local Postgres, then
set `POSTGRES_PORT=5433` for the host-run commands above.

### The seeded personas

| Persona | Phone | Story | What shows up |
|---|---|---|---|
| **Priya Sharma** | `9000000001` | Type 2 diabetes + hypertension | declining→recovering DHS, `added_sugar` nudge |
| **Ravi Menon** | `9000000002` | manages his father's meds — on Warfarin | `vitamin_k` drug-interaction nudge |
| **Aarav Iyer** | `9000000003` | tree-nut + dairy allergy | repeated allergen hard-stops, `nut_allergen` nudge |
| **Meera Nair** | `9000000004` | health-optimiser, no conditions | clean improving trend, **no** nudge |

`seed_demo_users` also prints a ready-to-use access token per persona (for curl /
`--dart-define`).

## 2. Build the app for the demo backend

Point it at wherever the backend is reachable from the device (LAN IP, ngrok,
or `10.0.2.2:8000` from an Android emulator running on the same machine):

```bash
cd mobile
tool/build_demo.sh http://<host-or-lan-ip>:8000            # -> app-release.apk
# or:  tool/build_demo.ps1 -ApiBaseUrl http://<...>:8000
```

This is a `flutter build --release` with:

| dart-define | value | effect |
|---|---|---|
| `API_BASE_URL` | the demo backend | where every request goes |
| `DEBUG_GALLERY` | `false` | the `/debug` screen-gallery route is **not registered** |
| `DEMO_MODE` | `true` | a small "DEMO DATA" chip on the home header |

Install `build/app/outputs/flutter-apk/app-release.apk` on the device.

> **Build prerequisite:** the Android Gradle plugin needs **JDK 17 or 21**
> (Gradle 8.14 doesn't support JDK 24+). If `flutter build apk` fails with a bare
> `* What went wrong: 26`, point Flutter at a supported JDK:
> `flutter config --jdk-dir="<path-to-jdk-17-or-21>"`. The CI `mobile-e2e` job
> already pins Temurin 17. `flutter build bundle --release` (Dart + assets only,
> no Gradle) works on any JDK and is enough to sanity-check the release compile.

## 3. Sign in during the demo

1. Open the app → phone screen → enter e.g. `9000000001`.
2. The demo backend echoes the code; the app stages it into the boxes
   automatically. Tap **Verified — continue**.
3. Because these accounts already have a profile, onboarding is skipped — you
   land straight on Home with populated Trends / History and a live nudge.

## What is *not* in the release build

Confirmed by `mobile/test/release_config_test.dart` and existing tests:

- **No debug banner** — `debugShowCheckedModeBanner: false` on every `MaterialApp`.
- **No `/debug` screen gallery** — the route isn't registered when
  `DEBUG_GALLERY` is false (the default for any `--release` build). Navigating
  there redirects to `/onboarding` or `/app`.
- **No `print` / `debugPrint` in `lib/`**, **no Dio payload-logging interceptor**,
  **no analytics / crash SDK** — `no_pii_telemetry_test.dart`.
- `assert(...)` calls are compiled out by `--release`.
- The `FLUTTER_TEST` env guards in the storage / timezone / cache layers are
  inert outside `flutter test`.

The backend running `ENVIRONMENT=development` (so the OTP is echoed) is a
**demo-only** choice — a real deployment sets `ENVIRONMENT=production`, which
refuses to boot on the placeholder secrets and stops echoing the OTP
(see `docs/security-audit-2026-08.md`).
