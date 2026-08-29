// Phase 6.3 — offline-first: cached product + history are served when the
// backend is unreachable, tagged so the UI shows an "offline" state (not a
// hard failure).

import 'dart:convert';
import 'dart:typed_data';

import 'package:carecart/src/core/api_client.dart';
import 'package:carecart/src/core/connectivity.dart';
import 'package:carecart/src/core/history_api.dart';
import 'package:carecart/src/core/local_cache.dart';
import 'package:carecart/src/core/product_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineReach extends Reachability {
  @override
  Reach build() => Reach.offline;
}

class _DeadAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) =>
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
  @override
  void close({bool force = false}) {}
}

Dio _deadDio() {
  final d = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  d.httpClientAdapter = _DeadAdapter();
  return d;
}

ScannedProduct _p(String bc) => ScannedProduct(
      barcode: bc,
      name: 'Saved Crackers',
      ingredients: const ['Wheat flour', 'Iodised salt'],
      nutriments: const {'sodium_mg_100g': 900},
    );

void main() {
  group('reachability notifier', () {
    test('starts unknown, flips on mark, is idempotent', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(reachabilityProvider), Reach.unknown);
      expect(c.read(isOfflineProvider), isFalse);

      c.read(reachabilityProvider.notifier).markUnreachable();
      expect(c.read(reachabilityProvider), Reach.offline);
      expect(c.read(isOfflineProvider), isTrue);

      c.read(reachabilityProvider.notifier).markOk();
      expect(c.read(isOfflineProvider), isFalse);
    });

    test('the dio interceptor marks offline on a connection error', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final dio = c.read(dioProvider); // real interceptors attached
      dio.httpClientAdapter = _DeadAdapter();
      try {
        await dio.get<void>('/anything');
      } on DioException {/* expected */}
      expect(c.read(isOfflineProvider), isTrue);
    });

    test('dio has all three timeouts set so a call can never hang forever', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final o = c.read(dioProvider).options;
      expect(o.connectTimeout, isNotNull);
      expect(o.receiveTimeout, isNotNull);
      expect(o.sendTimeout, isNotNull);
    });
  });

  group('history — offline falls back to the on-device snapshot', () {
    test('HistoryOffline when the fetch fails and a snapshot exists', () async {
      final cache = LocalCache(MemoryKV());
      await cache.putHistory([
        ScanHistoryEntry(
            id: '1',
            productName: 'Yesterday oats',
            score: 95,
            tier: 'safe',
            scannedAt: DateTime.now().toUtc().subtract(const Duration(hours: 20))),
      ]);

      final c = ProviderContainer(overrides: [
        localCacheProvider.overrideWithValue(cache),
        reachabilityProvider.overrideWith(_OfflineReach.new),
        historyProvider.overrideWithValue(
            ({int limit = 20, int offset = 0}) async =>
                const HistoryFailed('No connection to the server.')),
      ]);
      addTearDown(c.dispose);

      final r = await c.read(historyPageProvider.future);
      expect(r, isA<HistoryOffline>());
      final o = r as HistoryOffline;
      expect(o.items.single.productName, 'Yesterday oats');
      expect(o.cachedAt.isBefore(DateTime.now()), isTrue);
    });

    test('a hard failure with no snapshot stays HistoryFailed', () async {
      final c = ProviderContainer(overrides: [
        localCacheProvider.overrideWithValue(LocalCache(MemoryKV())),
        reachabilityProvider.overrideWith(_OfflineReach.new),
        historyProvider.overrideWithValue(
            ({int limit = 20, int offset = 0}) async =>
                const HistoryFailed('No connection to the server.')),
      ]);
      addTearDown(c.dispose);
      expect(await c.read(historyPageProvider.future), isA<HistoryFailed>());
    });

    test('a successful fetch is snapshotted for next time', () async {
      final cache = LocalCache(MemoryKV());
      final page = HistoryPage.fromJson({
        'items': [
          {'id': '9', 'product_name': 'Fresh', 'score': 80, 'tier': 'safe',
           'scanned_at': DateTime.now().toUtc().toIso8601String(), 'key_reasons': []}
        ],
        'total': 1, 'limit': 50, 'offset': 0, 'has_more': false,
      });
      final c = ProviderContainer(overrides: [
        localCacheProvider.overrideWithValue(cache),
        historyProvider.overrideWithValue(
            ({int limit = 20, int offset = 0}) async => HistoryLoaded(page)),
      ]);
      addTearDown(c.dispose);

      expect(await c.read(historyPageProvider.future), isA<HistoryLoaded>());
      final snap = await cache.getHistory();
      expect(snap!.items.single.productName, 'Fresh');
    });
  });

  group('product lookup — offline serves the saved copy', () {
    test('cached ProductFound(fromLocalCache) when the lookup fails offline',
        () async {
      final cache = LocalCache(MemoryKV());
      await cache.putProduct(_p('8901234567890'));

      final c = ProviderContainer(overrides: [
        localCacheProvider.overrideWithValue(cache),
        dioProvider.overrideWithValue(_deadDio()),
        reachabilityProvider.overrideWith(_OfflineReach.new),
      ]);
      addTearDown(c.dispose);

      final r = await c.read(productLookupProvider)('8901234567890');
      expect(r, isA<ProductFound>());
      final p = (r as ProductFound).product;
      expect(p.fromLocalCache, isTrue);
      expect(p.stale, isTrue);
      expect(p.displayName, 'Saved Crackers');
      expect(p.ingredients, ['Wheat flour', 'Iodised salt']);
    });

    test('no cache entry → the error is surfaced, not a silent success',
        () async {
      final c = ProviderContainer(overrides: [
        localCacheProvider.overrideWithValue(LocalCache(MemoryKV())),
        dioProvider.overrideWithValue(_deadDio()),
        reachabilityProvider.overrideWith(_OfflineReach.new),
      ]);
      addTearDown(c.dispose);
      expect(await c.read(productLookupProvider)('0000'), isA<ProductLookupError>());
    });

    test('a successful lookup is cached', () async {
      final cache = LocalCache(MemoryKV());
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
      dio.httpClientAdapter = _OkAdapter(jsonEncode({
        'barcode': '111', 'name': 'Live Oats', 'ingredients': ['Oats'],
        'nutriments': {'fiber_g_100g': 10},
      }));
      final c = ProviderContainer(overrides: [
        localCacheProvider.overrideWithValue(cache),
        dioProvider.overrideWithValue(dio),
      ]);
      addTearDown(c.dispose);

      final r = await c.read(productLookupProvider)('111');
      expect(r, isA<ProductFound>());
      expect((await cache.getProduct('111'))!.product.displayName, 'Live Oats');
    });
  });
}

class _OkAdapter implements HttpClientAdapter {
  _OkAdapter(this.body);
  final String body;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      ResponseBody.fromString(body, 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
  @override
  void close({bool force = false}) {}
}
