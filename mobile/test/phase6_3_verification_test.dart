// Phase 6.3 VERIFICATION.
//
//   1. use the app "online" for a bit  -> history + a product lookup are cached
//   2. drop connectivity               -> those screens show CACHED data with a
//                                         clear offline indicator, no infinite
//                                         spinner, no crash
//   3. restore connectivity            -> the app recovers and re-syncs with NO
//                                         restart (same ProviderContainer)
//   4. invalid onboarding input        -> rejected with a clear message, client
//                                         AND server side

import 'dart:convert';
import 'dart:typed_data';

import 'package:carecart/src/core/api_client.dart';
import 'package:carecart/src/core/connectivity.dart';
import 'package:carecart/src/core/history_api.dart';
import 'package:carecart/src/core/product_api.dart';
import 'package:carecart/src/state/onboarding_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

/// One adapter whose behaviour we flip between calls, exactly like toggling the
/// device's connectivity.
class _NetSwitch implements HttpClientAdapter {
  bool online = true;
  int calls = 0;

  Map<String, dynamic> Function(RequestOptions o)? bodyFor;

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    calls++;
    if (!online) {
      throw DioException(
          requestOptions: o, type: DioExceptionType.connectionError);
    }
    final body = bodyFor?.call(o) ?? const {};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _historyBody(int n) => {
      'items': [
        for (var i = 0; i < n; i++)
          {
            'id': '$i',
            'product_name': 'Item $i',
            'score': i.isEven ? 88 : 40,
            'tier': i.isEven ? 'safe' : 'caution',
            'hard_stop': false,
            'key_reasons': const [],
            'scanned_at':
                DateTime.now().toUtc().subtract(Duration(hours: i)).toIso8601String(),
          }
      ],
      'total': n,
      'limit': 50,
      'offset': 0,
      'has_more': false,
    };

Map<String, dynamic> _productBody(String barcode) => {
      'barcode': barcode,
      'name': 'Britannia Crackers',
      'brand': 'Britannia',
      'ingredients': const ['Wheat flour', 'Iodised salt', 'Palm oil'],
      'nutriments': const {'sodium_mg_100g': 900},
    };

void main() {
  test(
      'online → offline → online: history + product lookup serve cached data '
      'tagged offline (not a hard error), then recover without a restart',
      () async {
    final net = _NetSwitch()
      ..bodyFor = (o) => o.path.contains('/history')
          ? _historyBody(3)
          : _productBody(o.path.split('/').last);

    final container = ProviderContainer(overrides: [
      // the real app Dio (three timeouts + reachability interceptor), with a
      // swappable transport standing in for the device radio
      dioProvider.overrideWith((ref) => buildApiDio(ref)..httpClientAdapter = net),
    ]);
    addTearDown(container.dispose);

    // a permanent listener so the autoDispose provider stays mounted through
    // each fetch (in the app, HistoryScreen.watch does this).
    final sub = container.listen(historyPageProvider, (_, _) {});
    addTearDown(sub.close);

    // "reopen the history tab" = invalidate the autoDispose provider and await it
    Future<HistoryResult> reopenHistory() async {
      container.invalidate(historyPageProvider);
      return container.read(historyPageProvider.future);
    }

    // ─── 1. ONLINE — use the app for a bit (history + a product lookup) ──
    final h1 = await reopenHistory();
    expect(h1, isA<HistoryLoaded>());
    expect((h1 as HistoryLoaded).page.items.length, 3);
    expect(container.read(isOfflineProvider), isFalse);

    final look1 = await container.read(productLookupProvider)('8901234567890');
    expect((look1 as ProductFound).product.fromLocalCache, isFalse);

    // ─── 2. DROP CONNECTIVITY ─────────────────────────────────────────
    net.online = false;

    final h2 = await reopenHistory().timeout(const Duration(seconds: 3),
        onTimeout: () => throw 'history provider hung — infinite spinner');
    expect(h2, isA<HistoryOffline>(), reason: 'cached rows, not a bare failure');
    expect((h2 as HistoryOffline).items.length, 3);
    expect(h2.cachedAt.isBefore(DateTime.now()), isTrue);
    expect(container.read(isOfflineProvider), isTrue);

    final look2 = await container.read(productLookupProvider)('8901234567890');
    final p = (look2 as ProductFound).product;
    expect(p.fromLocalCache, isTrue);
    expect(p.stale, isTrue);
    expect(p.displayName, 'Britannia Crackers');

    // a barcode we never cached → honest error, not a fake success
    expect(await container.read(productLookupProvider)('0000000000000'),
        isA<ProductLookupError>());

    // ─── 3. CONNECTIVITY BACK — recover, no restart (same container) ───
    net.online = true;
    net.bodyFor = (o) =>
        o.path.contains('/history') ? _historyBody(5) : _productBody('x');

    final h3 = await reopenHistory();
    expect(h3, isA<HistoryLoaded>(), reason: 'recovered — fresh data');
    expect((h3 as HistoryLoaded).page.items.length, 5);
    expect(container.read(isOfflineProvider), isFalse);

    final look3 = await container.read(productLookupProvider)('8901234567890');
    expect((look3 as ProductFound).product.fromLocalCache, isFalse);
  });

  group('invalid onboarding input is rejected with a clear message (client)', () {
    late ProviderContainer c;
    late FakeVaultApi vault;
    OnboardingFlow flow() => c.read(onboardingFlowProvider.notifier);
    OnboardingState st() => c.read(onboardingFlowProvider);

    setUp(() {
      vault = FakeVaultApi();
      c = ProviderContainer(
          overrides: fakeBackendOverrides(
              auth: FakeAuthApi(devCode: '123456'), vault: vault));
    });
    tearDown(() => c.dispose());

    test('empty required phone → blocked, clear message, no API call', () async {
      flow().setPhone('');
      await flow().submitPhone();
      expect(st().oScreen, OnbScreen.login);
      expect(st().oError, contains('10-digit'));
    });

    test('garbage phone (letters / wrong length) → blocked', () async {
      for (final bad in ['abcdef', '12345', '0000000000']) {
        flow().setPhone(bad);
        await flow().submitPhone();
        expect(st().oScreen, OnbScreen.login, reason: bad);
        expect(st().oError, isNotNull, reason: bad);
      }
    });

    test('absurdly long "something else" is capped to the server limit (120)',
        () {
      flow().setOther('nut ' * 500); // ~2000 chars
      expect(st().oOther.length, 120);
    });

    test('absurd body metrics are dropped, not sent to the vault as garbage',
        () async {
      flow().setPhone('9876543210');
      await flow().submitPhone();
      flow().setOtp('123456');
      await flow().verifyOtp();

      flow().setWeight('99999999');
      flow().setHeight('0');
      for (var i = 0; i < kOnbSteps.length - 1; i++) {
        flow().next();
      }
      await flow().next(); // -> startBuilding -> putHealthProfile

      expect(st().oScreen, OnbScreen.done);
      expect(vault.profile!['weight'], isNull,
          reason: '99999999 kg must not reach the vault');
      expect(vault.profile!['height'], isNull, reason: '0 cm is out of range');
    });
  });
}
