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
python -m scripts.load_drug_catalog          # searchable medicine list (add-a-med picker)
python -m scripts.load_food_catalog          # searchable everyday-food dataset (Look it up)
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
refuses to boot on the placeholder secrets, stops echoing the OTP, and disables
`/docs` `/redoc` `/openapi.json` (see `docs/security-audit-2026-08.md`,
`test_no_internal_endpoints.py`).

---

## Getting it onto a physical Android phone

### 0. One-time: a build-compatible JDK

`flutter build apk` needs **JDK 17 or 21** (Gradle 8.14 rejects JDK 24+). Install
Temurin 21, then:

```powershell
flutter config --jdk-dir="C:\Program Files\Eclipse Adoptium\jdk-21.x.x-hotspot"
flutter doctor              # Android toolchain should be a clean check now
```

Enable **Developer options → USB debugging** on the phone, plug it in, accept the
RSA prompt, and confirm `flutter devices` lists it.

### 1. Run the demo backend on your laptop (phone reaches it over Wi-Fi)

```powershell
# from repo root
docker compose up -d postgres

cd backend
.\.venv\Scripts\Activate.ps1
copy .env.example .env                       # dev placeholders are fine
$env:POSTGRES_PORT = "5433"                  # docker-compose publishes 5433

alembic upgrade head
python -m scripts.load_risk_tables
python -m scripts.load_drug_catalog          # searchable medicine list (add-a-med picker)
python -m scripts.load_food_catalog          # searchable everyday-food dataset (Look it up)
python -m scripts.seed_demo_products
python -m scripts.seed_demo_users --reset    # prints the 4 persona phones

# bind to 0.0.0.0 so the phone can reach it, and open the port
netsh advfirewall firewall add rule name="carecart-demo" dir=in action=allow protocol=TCP localport=8000
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Find the laptop's Wi-Fi IPv4 (`ipconfig` → "Wireless LAN adapter Wi-Fi"), e.g.
`192.168.1.23`. From the **phone's browser** open
`http://192.168.1.23:8000/health` — you should get `{"status":"ok","db":"connected"}`.
(If it fails: same Wi-Fi? firewall? Corporate/hostel Wi-Fi often blocks
device-to-device — use a phone hotspot the laptop joins, or `ngrok http 8000` and
use the https URL below.)

### 2. Build & install the release APK

```powershell
cd ..\mobile
.\tool\build_demo.ps1 -ApiBaseUrl http://192.168.1.23:8000
#   == flutter build apk --release
#        --dart-define=API_BASE_URL=http://192.168.1.23:8000
#        --dart-define=DEBUG_GALLERY=false
#        --dart-define=DEMO_MODE=true

flutter install --release      # pushes app-release.apk to the connected phone
# or:  adb install -r build\app\outputs\flutter-apk\app-release.apk
# or:  copy the .apk to the phone and tap it (allow "install unknown apps")
```

### 3. Demo the personas on the phone

The app stores a session after first sign-in, so between personas **clear the
app's storage** (Settings → Apps → CareCart → Storage → *Clear storage*) — this
forgets the local session but keeps all four personas intact on the server. (The
in-app "Delete account" also works but removes that persona server-side; re-run
`seed_demo_users --reset` to bring them all back.)

For each persona:

1. Open the app → enter the phone (`9000000001` … `9000000004`).
2. The demo backend echoes the code; it auto-fills. Tap **Verified — continue**.
3. Onboarding is skipped (these accounts already have a profile) — you land on
   **Home** with data:
   - **History** tab — ~4 weeks of scans, grouped by day.
   - **Trends** tab — a Diet Health Score + the weekly line + safe/caution/avoid chips.
   - **Nudge** (home card → "What's driving it") — Priya: added sugar · Ravi:
     vitamin K · Aarav: tree nuts · **Meera: "Nothing to flag"** (by design).
   - A small **"DEMO DATA"** chip on the Home header.

### 4. Confirm the build is clean (do these yourself)

| Check | How | Expected |
|---|---|---|
| No debug banner | look at the top-right of any screen | nothing there |
| No debug menu / gallery | tap around the whole app | there is no `/debug` entry point — the route isn't in this build |
| No console logging of data | `adb logcat -s flutter` while using the app | no request/response bodies, no PII, no `print` spam |
| No internal endpoints | `curl http://192.168.1.23:8000/api/v1/admin` (and `/debug`, `/metrics`, `/internal`) | `404` every time — only the app's 24 endpoints respond |

### Wi-Fi-free alternative

```powershell
ngrok http 8000                                  # -> https://abcd-1234.ngrok-free.app
.\tool\build_demo.ps1 -ApiBaseUrl https://abcd-1234.ngrok-free.app
```
Works from any network; no firewall/LAN setup.
