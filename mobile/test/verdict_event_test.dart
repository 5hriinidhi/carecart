// verdictEventProvider — the seam Phase 5 diet logging hooks into. Every
// SUCCESSFUL scanBarcode() emits a VerdictEvent here; a not-found or errored
// scan does not.

import 'package:carecart/src/core/product_api.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:carecart/src/state/verdict_events.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _product = ScannedProduct(
  barcode: '8901234567890',
  name: 'Palak Sev',
  brand: 'Test',
  ingredients: ['Spinach', 'Salt'],
  nutriments: {'sodium_mg_100g': 900.0},
);

ScanVerdict _verdict = ScanVerdict.fromJson(const {
  'score': 55,
  'tier': 'caution',
  'hard_stop': false,
  'reasons': [
    {'kind': 'condition_ceiling', 'severity': 'moderate', 'points': 16, 'title': 'High sodium'}
  ],
  'medications': <Map<String, dynamic>>[],
  'risk_compounds': {'sodium': 0.9},
  'unverified': <String>[],
  'unverified_count': 0,
});

ProviderContainer _c({
  required ProductLookup Function(String) lookup,
  ScanVerdictOutcome Function()? verdict,
}) {
  final c = ProviderContainer(overrides: [
    productLookupProvider.overrideWithValue((code) async => lookup(code)),
    scanVerdictProvider.overrideWithValue((
            {required List<String> ingredients,
            Map<String, num> nutriments = const {},
            String? barcode,
            String? productName}) async =>
        verdict?.call() ?? ScanVerdictReady(_verdict)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('a successful scan emits one VerdictEvent with the barcode + verdict', () async {
    final c = _c(lookup: (_) => const ProductFound(_product));
    final seen = <VerdictEvent?>[];
    c.listen(verdictEventProvider, (_, next) => seen.add(next), fireImmediately: false);

    expect(c.read(verdictEventProvider), isNull); // nothing before the first scan

    await c.read(mainAppProvider.notifier).scanBarcode('8901234567890');

    final ev = c.read(verdictEventProvider);
    expect(ev, isNotNull);
    expect(ev!.barcode, '8901234567890');
    expect(ev.productName, 'Palak Sev');
    expect(ev.product?.barcode, '8901234567890');
    expect(identical(ev.verdict, c.read(mainAppProvider).verdict), isTrue);
    expect(ev.at, isA<DateTime>());
    expect(seen.whereType<VerdictEvent>().length, 1); // Phase 5 listener fires once
  });

  test('a "not found" scan does NOT emit an event', () async {
    final c = _c(lookup: (code) => ProductNotFound(code, fallbackToOcr: true));
    await c.read(mainAppProvider.notifier).scanBarcode('0000000000000');
    expect(c.read(verdictEventProvider), isNull);
  });

  test('a failed verdict does NOT emit an event', () async {
    final c = _c(
      lookup: (_) => const ProductFound(_product),
      verdict: () => const ScanVerdictFailed('boom'),
    );
    await c.read(mainAppProvider.notifier).scanBarcode('8901234567890');
    expect(c.read(verdictEventProvider), isNull);
    expect(c.read(mainAppProvider).verdictPhase, VerdictPhase.error);
  });

  test('a second successful scan emits a fresh event', () async {
    final c = _c(lookup: (_) => const ProductFound(_product));
    await c.read(mainAppProvider.notifier).scanBarcode('8901234567890');
    final first = c.read(verdictEventProvider);
    c.read(mainAppProvider.notifier).goScan();
    await c.read(mainAppProvider.notifier).scanBarcode('8901234567890');
    final second = c.read(verdictEventProvider);
    expect(second, isNotNull);
    expect(identical(first, second), isFalse);
  });
}
