import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'history_api.dart';
import 'product_api.dart';

/// On-device cache so the History screen and a re-scanned product still show
/// something useful with no connectivity (Phase 6.3).
///
/// Small structured blobs — a bounded set of recent products + the user's own
/// first history page — behind a tiny key/value seam. Backed by
/// `shared_preferences` on device; an in-memory map under `flutter test` (the
/// plugin channel is absent there) and, in principle, anywhere else. If this
/// ever needs thousands of rows, swap the shared_preferences impl for a `sqflite`/`Hive`
/// impl — nothing else in the app touches storage.
abstract class KvStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class _SharedPrefsKV implements KvStore {
  final Future<SharedPreferences> _p = SharedPreferences.getInstance();
  @override
  Future<String?> read(String k) async => (await _p).getString(k);
  @override
  Future<void> write(String k, String v) async => (await _p).setString(k, v);
  @override
  Future<void> remove(String k) async => (await _p).remove(k);
}

class MemoryKV implements KvStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String k) async => _m[k];
  @override
  Future<void> write(String k, String v) async => _m[k] = v;
  @override
  Future<void> remove(String k) async => _m.remove(k);
}

bool get _underFlutterTest =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

class LocalCache {
  LocalCache([KvStore? kv])
      : _kv = kv ?? (_underFlutterTest ? MemoryKV() : _SharedPrefsKV());

  final KvStore _kv;

  static const _kProducts = 'cc_cache_products_v1';
  static const _kHistory = 'cc_cache_history_v1';
  static const _maxProducts = 30;
  static const _maxHistory = 100;

  // ---------------------------------------------------------------- products
  Future<void> putProduct(ScannedProduct p) async {
    if (p.barcode.isEmpty) return;
    final map = await _readMap(_kProducts);
    map[p.barcode] = {
      'p': p.copyWith(cached: false, stale: false, fromLocalCache: false).toJson(),
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    if (map.length > _maxProducts) {
      final oldest = map.entries.toList()
        ..sort((a, b) => _at(a.value).compareTo(_at(b.value)));
      for (final e in oldest.take(map.length - _maxProducts)) {
        map.remove(e.key);
      }
    }
    await _kv.write(_kProducts, jsonEncode(map));
  }

  Future<CachedProduct?> getProduct(String barcode) async {
    final entry = (await _readMap(_kProducts))[barcode];
    if (entry is! Map) return null;
    try {
      return CachedProduct(
        product:
            ScannedProduct.fromJson((entry['p'] as Map).cast<String, dynamic>()),
        cachedAt: _at(entry),
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- history
  Future<void> putHistory(List<ScanHistoryEntry> items) async {
    await _kv.write(
      _kHistory,
      jsonEncode({
        'items': [for (final e in items.take(_maxHistory)) e.toJson()],
        'at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<CachedHistory?> getHistory() async {
    final raw = await _kv.read(_kHistory);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return CachedHistory(
        items: [
          for (final e in (j['items'] as List))
            ScanHistoryEntry.fromJson((e as Map).cast<String, dynamic>())
        ],
        cachedAt:
            DateTime.tryParse(j['at'] as String? ?? '')?.toLocal() ?? DateTime(0),
      );
    } catch (_) {
      return null;
    }
  }

  /// Wipe everything (on sign-out / account deletion — cached PHI must not
  /// outlive the session).
  Future<void> clear() async {
    await _kv.remove(_kProducts);
    await _kv.remove(_kHistory);
  }

  // ---------------------------------------------------------------- helpers
  Future<Map<String, dynamic>> _readMap(String key) async {
    final raw = await _kv.read(key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  DateTime _at(Object? entry) =>
      DateTime.tryParse((entry as Map?)?['at'] as String? ?? '')?.toLocal() ??
      DateTime(0);
}

class CachedProduct {
  const CachedProduct({required this.product, required this.cachedAt});
  final ScannedProduct product;
  final DateTime cachedAt;
}

class CachedHistory {
  const CachedHistory({required this.items, required this.cachedAt});
  final List<ScanHistoryEntry> items;
  final DateTime cachedAt;
}

final localCacheProvider = Provider<LocalCache>((ref) => LocalCache());
