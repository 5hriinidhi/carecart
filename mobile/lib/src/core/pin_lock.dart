import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A 4–6 digit PIN, set by the user in the app, that guards adding or removing a
/// medication. Only a salted SHA-256 hash is stored — never the PIN itself — and
/// it lives in the OS keychain / keystore via [FlutterSecureStorage], the same
/// place the auth tokens go. It never leaves the device.

bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

/// Where the salt + hash live between launches.
abstract class PinStore {
  Future<({String salt, String hash})?> read();
  Future<void> write({required String salt, required String hash});
  Future<void> clear();
}

class SecurePinStore implements PinStore {
  SecurePinStore([FlutterSecureStorage? s])
      : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static const _kSalt = 'cc_med_pin_salt_v1';
  static const _kHash = 'cc_med_pin_hash_v1';

  @override
  Future<({String salt, String hash})?> read() async {
    try {
      final salt = await _s.read(key: _kSalt);
      final hash = await _s.read(key: _kHash);
      if (salt == null || hash == null) return null;
      return (salt: salt, hash: hash);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write({required String salt, required String hash}) async {
    await _s.write(key: _kSalt, value: salt);
    await _s.write(key: _kHash, value: hash);
  }

  @override
  Future<void> clear() async {
    try {
      await _s.delete(key: _kSalt);
      await _s.delete(key: _kHash);
    } catch (_) {/* nothing stored */}
  }
}

/// In-memory fallback for `flutter test` / integration_test and web.
class MemoryPinStore implements PinStore {
  ({String salt, String hash})? _v;
  @override
  Future<({String salt, String hash})?> read() async => _v;
  @override
  Future<void> write({required String salt, required String hash}) async =>
      _v = (salt: salt, hash: hash);
  @override
  Future<void> clear() async => _v = null;
}

bool get _underFlutterTest =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

final pinStoreProvider = Provider<PinStore>((ref) {
  if (kIsWeb || _underFlutterTest) return MemoryPinStore();
  return SecurePinStore();
});

String _hash(String salt, String pin) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();

String _newSalt() {
  final r = Random.secure();
  return List<int>.generate(16, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Set / check / clear the medications PIN. All work goes through [PinStore]; no
/// PIN or reversible form is ever persisted.
class PinLock {
  PinLock(this._store);
  final PinStore _store;

  Future<bool> isSet() async => (await _store.read()) != null;

  /// Create or replace the PIN. Throws [ArgumentError] on a malformed PIN.
  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) {
      throw ArgumentError('PIN must be 4–6 digits.');
    }
    final salt = _newSalt();
    await _store.write(salt: salt, hash: _hash(salt, pin));
  }

  /// True if [pin] matches the stored hash. False if none is set.
  Future<bool> verify(String pin) async {
    final rec = await _store.read();
    if (rec == null) return false;
    return _hash(rec.salt, pin) == rec.hash;
  }

  /// Forget the PIN (called on sign-out / account deletion).
  Future<void> clear() => _store.clear();
}

final pinLockProvider =
    Provider<PinLock>((ref) => PinLock(ref.read(pinStoreProvider)));
