import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time switches (Phase 6.4 — judge-ready build).
///
/// A `--release` build strips asserts and flips `kDebugMode` to false, so the
/// dev-only debug gallery disappears by default. Everything here can also be set
/// explicitly at build time, e.g.
///
///   flutter build apk --release \
///     --dart-define=API_BASE_URL=https://demo.carecart.example \
///     --dart-define=DEBUG_GALLERY=false \
///     --dart-define=DEMO_MODE=true

/// The `/debug` screen-gallery route. Off in any release build unless a build
/// explicitly turns it back on.
const bool kEnableDebugGallery = bool.fromEnvironment(
  'DEBUG_GALLERY',
  defaultValue: kDebugMode,
);

/// This is a seeded demo backend (personas + history pre-loaded). Purely
/// cosmetic — surfaces a small "Demo data" chip so no one mistakes the seeded
/// history for their own.
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE');

/// Overridable in tests. Reads the compile-time flag by default.
final debugGalleryEnabledProvider = Provider<bool>((ref) => kEnableDebugGallery);
