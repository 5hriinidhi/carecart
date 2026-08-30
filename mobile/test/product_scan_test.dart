// MainApp.scanProduct — a real barcode scan: look the code up and, if it's in
// the database, show the product's facts (screen -> MainScreen.product). A miss
// or an error keeps the user on the scan screen with a banner. No verdict.

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
  test('found -> product screen, state.product set, no verdict', () async {
    final c = _container((_) async => const ProductFound(_product));
    final app = c.read(mainAppProvider.notifier);

    await app.scanProduct('3017620422003');

    final s = c.read(mainAppProvider);
    expect(s.lookup, LookupPhase.found);
    expect(s.barcode, '3017620422003');
    expect(s.product?.name, 'Nutella');
    expect(s.screen, MainScreen.product);
    expect(s.ocrFallback, isFalse);
    expect(s.verdict, isNull);
    expect(s.verdictPhase, VerdictPhase.idle);
  });

  test('not found -> stays on scan, ocrFallback flag is raised', () async {
    final c = _container((code) async => ProductNotFound(code, fallbackToOcr: true));
    final app = c.read(mainAppProvider.notifier);

    await app.scanProduct('0000000000000');

    final s = c.read(mainAppProvider);
    expect(s.lookup, LookupPhase.notFound);
    expect(s.screen, MainScreen.scan);
    expect(s.ocrFallback, isTrue);
    expect(s.product, isNull);
  });

  test('error -> stays on scan, lookup == error with the message', () async {
    final c = _container((_) async => const ProductLookupError('No connection to the server.'));
    final app = c.read(mainAppProvider.notifier);

    await app.scanProduct('123456789012');

    final s = c.read(mainAppProvider);
    expect(s.lookup, LookupPhase.error);
    expect(s.screen, MainScreen.scan);
    expect(s.lookupError, 'No connection to the server.');
  });

  test('a thrown lookup is caught, not propagated', () async {
    final c = _container((_) async => throw StateError('boom'));
    final app = c.read(mainAppProvider.notifier);

    await app.scanProduct('123456789012');
    expect(c.read(mainAppProvider).lookup, LookupPhase.error);
    expect(c.read(mainAppProvider).screen, MainScreen.scan);
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

    await c.read(mainAppProvider.notifier).scanProduct('3017620422003');
    expect(seen, LookupPhase.looking);
    expect(phaseWhenAsked, LookupPhase.looking);
  });

  test('empty / whitespace barcode is a no-op', () async {
    var called = false;
    final c = _container((_) async {
      called = true;
      return const ProductFound(_product);
    });
    await c.read(mainAppProvider.notifier).scanProduct('   ');
    expect(called, isFalse);
    expect(c.read(mainAppProvider).lookup, LookupPhase.idle);
    expect(c.read(mainAppProvider).screen, MainScreen.home);
  });

  test('dismissLookup + goScan reset the lookup state', () async {
    final c = _container((code) async => ProductNotFound(code));
    final app = c.read(mainAppProvider.notifier);

    await app.scanProduct('0000000000000');
    expect(c.read(mainAppProvider).lookup, LookupPhase.notFound);

    app.dismissLookup();
    expect(c.read(mainAppProvider).lookup, LookupPhase.idle);
    expect(c.read(mainAppProvider).ocrFallback, isFalse);

    await app.scanProduct('0000000000000');
    app.goScan();
    expect(c.read(mainAppProvider).lookup, LookupPhase.idle);
  });

  test('a superseded scan does not clobber the newer one', () async {
    // first lookup is slow, second resolves immediately with a different result
    final c = ProviderContainer(overrides: [
      productLookupProvider.overrideWithValue((code) async {
        if (code == '111') {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return const ProductFound(_product);
        }
        return ProductNotFound(code);
      }),
    ]);
    addTearDown(c.dispose);
    final app = c.read(mainAppProvider.notifier);

    final slow = app.scanProduct('111');
    await app.scanProduct('222'); // supersedes
    await slow;

    final s = c.read(mainAppProvider);
    expect(s.barcode, '222');
    expect(s.lookup, LookupPhase.notFound, reason: 'stale 111 result is ignored');
    expect(s.screen, MainScreen.scan);
  });

  test('does not disturb the onboarding machine', () async {
    final c = _container((_) async => const ProductFound(_product));
    await c.read(mainAppProvider.notifier).scanProduct('3017620422003');
    expect(c.read(onboardingCompleteProvider), isFalse);
  });
}
