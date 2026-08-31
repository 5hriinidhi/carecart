# CareCart — mobile

Flutter app for CareCart. See the repo-root `README.md` for the product
overview and `DEMO.md` for the full runbook.

## Dev

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # emulator -> host backend
```

## Layout

```
lib/src/
  core/        theme + design tokens, api clients (dio), seams (auth, vault, drugs,
               foods, lifestyle, fit, me), on-device cache, PIN lock
  routing/     go_router config + the onboarding gate
  state/       onboarding_state (o*-prefixed wizard) + main_app_state (the shell)
  features/    one folder per screen group — onboarding, home, scan, result,
               product, facts (shared nutrition panel), fit, profile, meds,
               search, history, trends, nudge
  debug/       /debug screen gallery (release builds only when DEBUG_GALLERY=true)
  fixtures/    hardcoded demo data for the static screens
```

## Build flags (`--dart-define`)

| flag | default | effect |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:8000` | where every request goes |
| `DEBUG_GALLERY` | `kDebugMode` | registers the `/debug` route + the scan-screen demo picker |
| `DEMO_MODE` | `false` | a "DEMO DATA" chip on Home |

`tool/build_demo.sh` / `tool/build_demo.ps1` wrap a release build with the
demo-safe values.

## Tests

Widget/state tests drive the fully-wired flow against in-memory fakes
(`test/support/fake_backend.dart`). `integration_test/full_journey_test.dart` is
the end-to-end run against a real backend (CI's `mobile-e2e` job). Privacy is
enforced by `test/no_pii_telemetry_test.dart`.
