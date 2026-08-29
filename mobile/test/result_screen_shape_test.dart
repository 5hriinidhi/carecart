// The result screen renders the POST /scan/verdict shape ONLY — a live verdict
// or the Phase 2 fixture adapted by demoVerdict(). The tier label always comes
// from chipFor(score) (Phase 2.1), never a hand-set field.

import 'package:carecart/src/core/product_api.dart';
import 'package:carecart/src/core/severity.dart';
import 'package:carecart/src/core/theme.dart';
import 'package:carecart/src/features/result/result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: buildCareCartTheme(), home: Scaffold(body: child));

ScanVerdict _verdict(int score) => ScanVerdict(
      score: score,
      tier: 'ignored', // the screen derives the label from chipFor(score)
      hardStop: false,
      reasons: const [
        VerdictReason(
            kind: 'condition_ceiling',
            severity: 'moderate',
            points: 12,
            title: 'High sodium for Hypertension'),
      ],
    );

void main() {
  group('demoVerdict adapts the fixture into the real shape', () {
    test('score + tier come straight from the fixture score via chipFor', () {
      final v = demoVerdict('noodles');
      expect(v.score, 24);
      expect(v.tier, chipFor(24).tone.name); // 'avoid'
      expect(v.tier, 'avoid');
      expect(v.reasons, isNotEmpty);
      expect(v.reasons.first.title, 'Maltodextrin'); // fixture flag -> reason
    });

    test('a safe fixture maps through chipFor to a safe tier', () {
      final v = demoVerdict('chana');
      expect(v.score, 86);
      expect(v.tier, 'safe');
    });

    test('unknown id falls back, never throws', () {
      expect(() => demoVerdict('does-not-exist'), returnsNormally);
    });
  });

  group('chipFor renders the live score correctly on the screen', () {
    testWidgets('a live avoid verdict shows the score + "Avoid"', (tester) async {
      await tester.pumpWidget(_host(ResultScreen(verdict: _verdict(24))));
      expect(tester.widget<Text>(find.byKey(const Key('verdict-score'))).data, '24');
      expect(tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data, 'Avoid');
    });

    testWidgets('boundary: score 70 -> "Safe for you", 69 -> "Caution"',
        (tester) async {
      await tester.pumpWidget(_host(ResultScreen(verdict: _verdict(70))));
      expect(tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data,
          'Safe for you');

      await tester.pumpWidget(_host(ResultScreen(verdict: _verdict(69))));
      expect(
          tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data, 'Caution');

      await tester.pumpWidget(_host(ResultScreen(verdict: _verdict(45))));
      expect(
          tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data, 'Caution');

      await tester.pumpWidget(_host(ResultScreen(verdict: _verdict(44))));
      expect(
          tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data, 'Avoid');
    });

    testWidgets('the demo picker path renders through the same widget', (tester) async {
      await tester.pumpWidget(_host(const ResultScreen(productId: 'noodles')));
      expect(tester.widget<Text>(find.byKey(const Key('verdict-score'))).data, '24');
      expect(tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data, 'Avoid');
      expect(find.text('Why this verdict'), findsOneWidget);
      // the retired fixture sections are gone
      expect(find.text('Per serving, against your ceilings'), findsNothing);
      expect(find.text('Safer swaps, same shelf'), findsNothing);
    });

    testWidgets('hard_stop verdict shows the allergen badge', (tester) async {
      final v = ScanVerdict(
        score: 0,
        tier: 'avoid',
        hardStop: true,
        reasons: const [
          VerdictReason(
              kind: 'allergen', severity: 'high', points: 0, title: 'Contains peanut'),
        ],
      );
      await tester.pumpWidget(_host(ResultScreen(verdict: v)));
      expect(find.byKey(const Key('verdict-hardstop-badge')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data, 'Avoid');
    });
  });
}
