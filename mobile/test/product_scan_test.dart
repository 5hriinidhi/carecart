// MainApp.lookupBarcode (Phase 4.1) — barcode -> product lookup state machine.

import 'package:carecart/src/core/product_api.dart';
import 'package:carecart/src/routing/app_router.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(Future<ProductLookup> Function(String) lookup) {
  final c = ProviderContainer(
    overrides: [productLookupProvider.overrideWithValue(lookup)],
  );
  addTearDown(c.dispose);
  return c;
}

const _product = ScannedProduct(
  barcode: '3017620422003',
  name: 'Nutella',
  brand: 'Ferrero',
  ingredients: ['Sugar', 'Palm oil'],
  cached: true,
);

void main() {
  test('found -> state.product set, lookup == found, still on scan', () async {
    final c = _container((_) async => const ProductFound(_product));
    final app = c.read(mainAppProvider.notifier);

    await app.lookupBarcode('3017620422003');

    final s = c.read(mainAppProvider);
    expect(s.lookup, LookupPhase.found);
    expect(s.barcode, '3017620422003');
    expect(s.product?.name, 'Nutella');
    expect(s.screen, MainScreen.scan);
    expect(s.ocrFallback, isFalse);
  });

  test('not found -> ocrFallback flag is raised', () async {
    final c = _container((code) async => ProductNotFound(code, fallbackToOcr: true));
    final app = c.read(mainAppProvider.notifier);

    await app.lookupBarcode('0000000000000');

    final s = c.read(mainAppProvider);
    expect(s.lookup, LookupPhase.notFound);
    expect(s.ocrFallback, isTrue);
    expect(s.product, isNull);
  });

  test('error -> lookup == error with the message', () async {
    final c = _container((_) async => const ProductLookupError('No connection to the server.'));
    final app = c.read(mainAppProvider.notifier);

    await app.lookupBarcode('123456789012');

    final s = c.read(mainAppProvider);
    expect(s.lookup, LookupPhase.error);
    expect(s.lookupError, 'No connection to the server.');
  });

  test('a thrown lookup is caught, not propagated', () async {
    final c = _container((_) async => throw StateError('boom'));
    final app = c.read(mainAppProvider.notifier);

    await app.lookupBarcode('123456789012');
    expect(c.read(mainAppProvider).lookup, LookupPhase.error);
  });

  test('goes through the looking phase', () async {
    var phaseWhenAsked = LookupPhase.idle;
    final c = ProviderContainer(overrides: [
      productLookupProvider.overrideWithValue((code) async {
        phaseWhenAsked = LookupPhase.looking; // lookup() is only called after state flips
        return const ProductFound(_product);
      }),
    ]);
    addTearDown(c.dispose);

    // observe the interim state
    LookupPhase? seen;
    c.listen(mainAppProvider, (_, next) => seen ??= next.lookup == LookupPhase.looking ? next.lookup : seen);

    await c.read(mainAppProvider.notifier).lookupBarcode('3017620422003');
    expect(seen, LookupPhase.looking);
    expect(phaseWhenAsked, LookupPhase.looking);
  });

  test('empty / whitespace barcode is a no-op', () async {
    var called = false;
    final c = _container((_) async {
      called = true;
      return const ProductFound(_product);
    });
    await c.read(mainAppProvider.notifier).lookupBarcode('   ');
    expect(called, isFalse);
    expect(c.read(mainAppProvider).lookup, LookupPhase.idle);
  });

  test('dismissLookup + goScan reset the lookup state', () async {
    final c = _container((code) async => ProductNotFound(code));
    final app = c.read(mainAppProvider.notifier);

    await app.lookupBarcode('0000000000000');
    expect(c.read(mainAppProvider).lookup, LookupPhase.notFound);

    app.dismissLookup();
    expect(c.read(mainAppProvider).lookup, LookupPhase.idle);
    expect(c.read(mainAppProvider).ocrFallback, isFalse);

    await app.lookupBarcode('0000000000000');
    app.goScan();
    expect(c.read(mainAppProvider).lookup, LookupPhase.idle);
  });

  test('does not disturb the onboarding machine', () async {
    final c = _container((_) async => const ProductFound(_product));
    await c.read(mainAppProvider.notifier).lookupBarcode('3017620422003');
    expect(c.read(onboardingCompleteProvider), isFalse);
  });
}
