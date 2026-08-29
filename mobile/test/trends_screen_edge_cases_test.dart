// Phase 5 edge cases (Flutter / TrendsScreen):
//   * zero scans -> empty state, no chart, no divide-by-zero
//   * one scan   -> a single bucket, "not enough history" note, no chart
//   * one outlier scan dragging a week's mean -> a visible "skewed" note
//   * a tight week -> no skew note

import 'package:carecart/src/core/analytics_api.dart';
import 'package:carecart/src/core/theme.dart';
import 'package:carecart/src/features/trends/trends_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(TrendsResult result) => ProviderScope(
      overrides: [trendsProvider.overrideWith((ref) async => result)],
      child: MaterialApp(
        theme: buildCareCartTheme(),
        home: const Scaffold(body: TrendsScreen()),
      ),
    );

TrendBucket _bucket({
  required String label,
  required int scans,
  required double avg,
  required double median,
  required int min,
  required int max,
  int safe = 0,
  int caution = 0,
  int avoid = 0,
  int dhs = 70,
}) =>
    TrendBucket(
      periodStart: DateTime.utc(2026, 8, 3),
      label: label,
      scans: scans,
      avgScore: avg,
      medianScore: median,
      minScore: min,
      maxScore: max,
      safe: safe,
      caution: caution,
      avoid: avoid,
      dietHealthScore: dhs,
    );

void main() {
  testWidgets('zero scans -> empty state, no chart, no exception', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(TrendsLoaded(const Trends(
      timezone: 'UTC',
      totalScans: 0,
      dietHealthScore: 0,
      deltaSevenDay: 0,
      trend: 'steady',
    ))));
    await tester.pumpAndSettle();

    expect(find.byType(LineChart), findsNothing);
    expect(find.textContaining('Scan a few products'), findsOneWidget);
    expect(find.byKey(const Key('dhs-value')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one scan -> one bucket, "not enough history" note, no chart',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(TrendsLoaded(Trends(
      timezone: 'UTC',
      totalScans: 1,
      dietHealthScore: 82,
      deltaSevenDay: 0,
      trend: 'steady',
      weekly: [
        _bucket(
            label: '3 Aug',
            scans: 1,
            avg: 82,
            median: 82,
            min: 82,
            max: 82,
            safe: 1,
            dhs: 82),
      ],
    ))));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('dhs-value'))).data, '82');
    expect(find.byType(LineChart), findsNothing);
    expect(find.textContaining('Not enough history yet for a weekly line.'),
        findsOneWidget);
    expect(find.byKey(const Key('trend-skew-note')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one low outlier scan -> a visible "skewed average" note',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(TrendsLoaded(Trends(
      timezone: 'UTC',
      totalScans: 10,
      dietHealthScore: 85,
      deltaSevenDay: 1,
      trend: 'steady',
      weekly: [
        _bucket(
            label: '27 Jul',
            scans: 5,
            avg: 84,
            median: 90,
            min: 82,
            max: 92,
            safe: 5,
            dhs: 86),
        // latest week: four ~90s and one 8 -> mean 73.8, median 90
        _bucket(
            label: '3 Aug',
            scans: 5,
            avg: 73.8,
            median: 90,
            min: 8,
            max: 92,
            safe: 4,
            avoid: 1,
            dhs: 85),
      ],
    ))));
    await tester.pumpAndSettle();

    final note = find.byKey(const Key('trend-skew-note'));
    expect(note, findsOneWidget);
    final txt = tester.widget<Text>(note).data!;
    expect(txt, contains('One low scan (8)'));
    expect(txt, contains('3 Aug'));
    expect(txt, contains('74')); // avg rounded
    expect(txt, contains('90')); // median
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tight latest week -> no skew note', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(TrendsLoaded(Trends(
      timezone: 'UTC',
      totalScans: 8,
      dietHealthScore: 72,
      deltaSevenDay: 0,
      trend: 'steady',
      weekly: [
        _bucket(
            label: '27 Jul', scans: 4, avg: 71, median: 70, min: 64, max: 79, safe: 4),
        _bucket(
            label: '3 Aug', scans: 4, avg: 73, median: 72, min: 66, max: 80, safe: 4),
      ],
    ))));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trend-skew-note')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
