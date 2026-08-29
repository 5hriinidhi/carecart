import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'auth_api.dart';
import 'local_cache.dart';

/// Where the JWT pair lives between launches. The access token is also mirrored
/// into [authTokenProvider] (in memory) so [dioProvider] can attach it.
abstract class TokenStore {
  Future<({String access, String refresh})?> read();
  Future<void> write({required String access, required String refresh});
  Future<void> clear();
}

/// Real device storage — Keychain / Keystore-backed.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? s])
      : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static const _kAccess = 'cc_access_token';
  static const _kRefresh = 'cc_refresh_token';

  @override
  Future<({String access, String refresh})?> read() async {
    try {
      final a = await _s.read(key: _kAccess);
      final r = await _s.read(key: _kRefresh);
      if (a == null || a.isEmpty) return null;
      return (access: a, refresh: r ?? '');
    } catch (_) {
      return null; // corrupt store / locked keychain → treat as signed out
    }
  }

  @override
  Future<void> write({required String access, required String refresh}) async {
    try {
      await _s.write(key: _kAccess, value: access);
      await _s.write(key: _kRefresh, value: refresh);
    } catch (_) {/* best effort */}
  }

  @override
  Future<void> clear() async {
    try {
      await _s.delete(key: _kAccess);
      await _s.delete(key: _kRefresh);
    } catch (_) {/* best effort */}
  }
}

/// In-memory fallback for `flutter test` / integration_test (no platform
/// channel) and web. State lives for the process only.
class MemoryTokenStore implements TokenStore {
  ({String access, String refresh})? _v;

  @override
  Future<({String access, String refresh})?> read() async => _v;

  @override
  Future<void> write({required String access, required String refresh}) async {
    _v = (access: access, refresh: refresh);
  }

  @override
  Future<void> clear() async => _v = null;
}

bool get _underFlutterTest =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

final tokenStoreProvider = Provider<TokenStore>((ref) {
  if (kIsWeb || _underFlutterTest) return MemoryTokenStore();
  return SecureTokenStore();
});

/// Sign-in / sign-out actions, shared by onboarding and the profile sheet.
class AuthController {
  AuthController(this._ref);
  final Ref _ref;

  /// Persist the pair and make it live for API calls.
  Future<void> signIn(AuthSession session) async {
    await _ref.read(tokenStoreProvider).write(
          access: session.accessToken,
          refresh: session.refreshToken,
        );
    _ref.read(authTokenProvider.notifier).set(session.accessToken);
  }

  /// Forget the session locally (after account deletion, or a manual sign-out).
  /// Also wipes the on-device product / history cache — it holds PHI.
  Future<void> signOut() async {
    await _ref.read(tokenStoreProvider).clear();
    await _ref.read(localCacheProvider).clear();
    _ref.read(authTokenProvider.notifier).clear();
  }
}

final authControllerProvider =
    Provider<AuthController>((ref) => AuthController(ref));

/// Runs once at startup: load any stored access token into [authTokenProvider].
/// Resolves to `true` when a session was restored (skip onboarding), `false`
/// otherwise (show onboarding).
final authBootstrapProvider = FutureProvider<bool>((ref) async {
  final stored = await ref.read(tokenStoreProvider).read();
  if (stored == null) return false;
  ref.read(authTokenProvider.notifier).set(stored.access);
  return true;
});
