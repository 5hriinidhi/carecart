// Phase 4 Check — end to end through the app: scan a barcode -> GET the product
// -> POST /scan/verdict -> land on the result screen with the real score, tier
// and a reason that NAMES the actual conflict (not a generic message).
//
// The two network calls are stubbed at the provider boundary; everything after
// that (state machine, navigation, ResultScreen rendering) is the real app.

import 'package:carecart/src/core/product_api.dart';
import 'package:carecart/src/core/theme.dart';
import 'package:carecart/src/features/app_shell.dart';
import 'package:carecart/src/features/result/result_screen.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---- fixtures shaped exactly like the real backend responses ----

const _greensProduct = ScannedProduct(
  barcode: '8901234567890',
  name: 'Palak & Methi Multigrain Sev',
  brand: 'Haldiram',
  ingredients: ['Gram flour', 'Spinach', 'Fenugreek leaves', 'Iodised salt', 'Edible oil'],
  nutriments: {'sodium_mg_100g': 1180.0, 'saturated_fat_g_100g': 4.2},
  servingSize: '30 g',
);

const _cleanProduct = ScannedProduct(
  barcode: '3017620422003',
  name: 'Rolled Oats',
  brand: 'Quaker',
  ingredients: ['Wholegrain rolled oats'],
  nutriments: {'sugars_g_100g': 1.0, 'sodium_mg_100g': 4.0, 'fiber_g_100g': 10.0},
  servingSize: '40 g',
);

// what POST /scan/verdict returns for a user on warfarin + hypertension when the
// product carries vitamin K (greens) and 1180 mg sodium / 100 g
final _avoidVerdict = ScanVerdict.fromJson(const {
  'score': 27,
  'tier': 'avoid',
  'hard_stop': false,
  'reasons': [
    {
      'kind': 'drug_interaction',
      'severity': 'high',
      'points': 35,
      'title': 'Warfarin 5mg (Anticoagulant (vitamin K antagonist)) interacts with Vitamin K',
      'detail': 'Dietary vitamin K antagonises warfarin; fluctuating intake destabilises INR. '
          'Keep leafy-green / vitamin-K intake CONSISTENT day to day.',
    },
    {
      'kind': 'condition_ceiling',
      'severity': 'high',
      'points': 38,
      'title': 'High sodium for Hypertension',
      'detail': '1180.0 per 100 g vs a 500 per-100 g limit for hypertension. '
          'High sodium works directly against blood-pressure control.',
    },
  ],
  'medications': [
    {
      'name': 'Warfarin 5mg',
      'drug_classes': ['Anticoagulant (vitamin K antagonist)'],
      'identified': true,
    },
  ],
  'risk_compounds': {'vitamin_k': 0.9, 'sodium': 0.9},
  'unverified': <String>[],
  'unverified_count': 0,
});

final _safeVerdict = ScanVerdict.fromJson(const {
  'score': 100,
  'tier': 'safe',
  'hard_stop': false,
  'reasons': [
    {
      'kind': 'clear',
      'severity': 'info',
      'points': 0,
      'title': 'No conflicts found with your medications, conditions, or allergies.',
    },
  ],
  'medications': [
    {
      'name': 'Warfarin 5mg',
      'drug_classes': ['Anticoagulant (vitamin K antagonist)'],
      'identified': true,
    },
  ],
  'risk_compounds': <String, dynamic>{},
  'unverified': <String>[],
  'unverified_count': 0,
});

ProviderContainer _container({
  required ProductLookup Function(String) lookup,
  required ScanVerdict verdict,
}) {
  final c = ProviderContainer(overrides: [
    productLookupProvider.overrideWithValue((code) async => lookup(code)),
    scanVerdictProvider.overrideWithValue((
            {required List<String> ingredients,
            Map<String, num> nutriments = const {},
            String? barcode,
            String? productName}) async =>
        ScanVerdictReady(verdict)),
  ]);
  addTearDown(c.dispose);
  return c;
}

Widget _app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildCareCartTheme(), home: const MainAppShell()),
    );

void main() {
  testWidgets('CONFLICT scan → result screen shows tier=Avoid, real score, and a '
      'reason that names the actual conflict', (tester) async {
    final c = _container(
      lookup: (_) => const ProductFound(_greensProduct),
      verdict: _avoidVerdict,
    );
    await tester.pumpWidget(_app(c));
    c.read(mainAppProvider.notifier).goScan();
    await tester.pump();

    final sw = Stopwatch()..start();
    await c.read(mainAppProvider.notifier).scanBarcode('8901234567890');
    await tester.pumpAndSettle();
    sw.stop();

    // landed on the result screen
    expect(c.read(mainAppProvider).screen, MainScreen.result);
    expect(c.read(mainAppProvider).verdictPhase, VerdictPhase.done);
    expect(find.byType(ResultScreen), findsOneWidget);

    // tier + score are the real values, not a fixture
    expect(find.byKey(const Key('verdict-tier')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data, 'Avoid');
    expect(tester.widget<Text>(find.byKey(const Key('verdict-score'))).data, '27');

    // the reason NAMES the conflict — warfarin + vitamin K, and the sodium ceiling
    expect(find.textContaining('Warfarin'), findsWidgets);
    expect(find.textContaining('Vitamin K'), findsOneWidget);
    expect(find.textContaining('High sodium for Hypertension'), findsOneWidget);
    expect(find.textContaining('vs a 500 per-100 g limit'), findsOneWidget);
    // not a generic catch-all
    expect(find.textContaining('may not be suitable'), findsNothing);
    expect(find.textContaining('Please review'), findsNothing);

    // ignore: avoid_print
    print('CONFLICT scan — tap→result (state machine + navigation + render): '
        '${sw.elapsedMilliseconds} ms  (network stubbed at 0 ms)');
  });

  testWidgets('CLEAN scan → safe verdict, score 100, "no conflicts" reason',
      (tester) async {
    final c = _container(
      lookup: (_) => const ProductFound(_cleanProduct),
      verdict: _safeVerdict,
    );
    await tester.pumpWidget(_app(c));

    final sw = Stopwatch()..start();
    await c.read(mainAppProvider.notifier).scanBarcode('3017620422003');
    await tester.pumpAndSettle();
    sw.stop();

    expect(c.read(mainAppProvider).screen, MainScreen.result);
    expect(tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data, 'Safe for you');
    expect(tester.widget<Text>(find.byKey(const Key('verdict-score'))).data, '100');
    expect(find.textContaining('No conflicts found'), findsOneWidget);
    expect(find.byKey(const Key('verdict-hardstop-badge')), findsNothing);

    // ignore: avoid_print
    print('CLEAN scan — tap→result: ${sw.elapsedMilliseconds} ms  (network stubbed at 0 ms)');
  });

  testWidgets('the interim phases are observable, then it lands on the result',
      (tester) async {
    final c = _container(
      lookup: (_) => const ProductFound(_greensProduct),
      verdict: _avoidVerdict,
    );
    await tester.pumpWidget(_app(c));
    final seen = <VerdictPhase>[];
    c.listen(mainAppProvider, (_, n) => seen.add(n.verdictPhase));

    await c.read(mainAppProvider.notifier).scanBarcode('8901234567890');
    await tester.pumpAndSettle();

    // looking -> scoring -> done, and we end on the result screen
    expect(seen, containsAllInOrder([VerdictPhase.looking, VerdictPhase.scoring]));
    expect(c.read(mainAppProvider).verdictPhase, VerdictPhase.done);
    expect(c.read(mainAppProvider).screen, MainScreen.result);
  });

  testWidgets('a "not found" barcode does NOT jump to a verdict', (tester) async {
    final c = _container(
      lookup: (code) => ProductNotFound(code, fallbackToOcr: true),
      verdict: _safeVerdict,
    );
    await tester.pumpWidget(_app(c));
    c.read(mainAppProvider.notifier).goScan();
    await tester.pump();

    await c.read(mainAppProvider.notifier).scanBarcode('0000000000000');
    await tester.pumpAndSettle();

    final s = c.read(mainAppProvider);
    expect(s.screen, MainScreen.scan);
    expect(s.lookup, LookupPhase.notFound);
    expect(s.ocrFallback, isTrue);
    expect(s.verdict, isNull);
  });
}
