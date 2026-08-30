#!/usr/bin/env bash
# Judge-ready release build of the CareCart app, pointed at a seeded demo backend
# (Phase 6.4). Usage:
#
#   tool/build_demo.sh https://demo.carecart.example      # APK, release
#   tool/build_demo.sh http://192.168.1.20:8000  appbundle
#
# Notes:
#  * --release strips asserts and turns kDebugMode off, so DEBUG_GALLERY defaults
#    to false — the /debug screen-gallery route is not registered.
#  * DEMO_MODE=true shows a small "DEMO DATA" chip so seeded history isn't mistaken
#    for the judge's own scans.
#  * There is no debug banner (debugShowCheckedModeBanner: false), no print/
#    debugPrint in lib/, no Dio payload logger — all enforced by tests.
set -euo pipefail

API_BASE_URL="${1:?usage: build_demo.sh <API_BASE_URL> [apk|appbundle|ios]}"
TARGET="${2:-apk}"

cd "$(dirname "$0")/.."
flutter pub get

flutter build "$TARGET" \
  --release \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=DEBUG_GALLERY=false \
  --dart-define=DEMO_MODE=true

echo
echo "Built $TARGET (release) → API_BASE_URL=$API_BASE_URL"
case "$TARGET" in
  apk)       echo "  build/app/outputs/flutter-apk/app-release.apk" ;;
  appbundle) echo "  build/app/outputs/bundle/release/app-release.aab" ;;
esac
