// Phase 5.2 VERIFICATION (Flutter side).
//
// Renders the real TrendsScreen against the SAME aggregated numbers the backend
// verification produced for the 3-week seeded user, and confirms the fl_chart
// line plots exactly those weekly Diet Health Score values, the header shows the
// current score / delta / trend, and the tier chips show the summed counts.
//
//   backend GET /analytics/trends (tz=UTC) for that user returned:
//     DHS=73  delta_7d=+3  trend=improving   total_scans=9
//     week 3 Aug : n=3 avg 70.0  s/c/a 2/0/1  DHS 78
//     week 10 Aug: n=4 avg 52.5  s/c/a 1/2/1  DHS 62
//     week 17 Aug: n=2 avg 94.0  s/c/a 2/0/0  DHS 73

import 'package:carecart/src/core/analytics_api.dart';
import 'package:carecart/src/core/theme.dart';
import 'package:carecart/src/features/trends/trends_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _seededTrends = Trends(
  timezone: 'UTC',
  totalScans: 9,
  dietHealthScore: 73,
  deltaSevenDay: 3,
  trend: 'improving',
  weekly: [
    TrendBucket(
        periodStart: DateTime.utc(2026, 8, 3),
        label: '3 Aug',
        scans: 3,
        avgScore: 70.0,
        safe: 2,
        caution: 0,
        avoid: 1,
        dietHealthScore: 78),
    TrendBucket(
        periodStart: DateTime.utc(2026, 8, 10),
        label: '10 Aug',
        scans: 4,
        avgScore: 52.5,
        safe: 1,
        caution: 2,
        avoid: 1,
        dietHealthScore: 62),
    TrendBucket(
        periodStart: DateTime.utc(2026, 8, 17),
        label: '17 Aug',
        scans: 2,
        avgScore: 94.0,
        safe: 2,
        caution: 0,
        avoid: 0,
        dietHealthScore: 73),
  ],
  monthly: [
    TrendBucket(
        periodStart: DateTime.utc(2026, 8),
        label: 'Aug 2026',
        scans: 9,
        avgScore: 67.6,
        safe: 5,
        caution: 2,
        avoid: 2,
        dietHealthScore: 73),
  ],
);

Widget _app() => ProviderScope(
      overrides: [
        trendsProvider.overrideWith((ref) async => TrendsLoaded(_seededTrends)),
      ],
      child: MaterialApp(
        theme: buildCareCartTheme(),
        home: const Scaffold(body: TrendsScreen()),
      ),
    );

String _text(WidgetTester t, Key k) => t.widget<Text>(find.byKey(k)).data!;

void main() {
  testWidgets('the weekly chart plots exactly the seeded Diet Health Score values',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // header
    expect(_text(tester, const Key('dhs-value')), '73');
    expect(_text(tester, const Key('dhs-delta')), '+3');
    expect(find.textContaining('improving'), findsOneWidget);

    // the line chart: one bar, 3 points, y == the weekly diet_health_score list
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final data = chart.data;
    expect(data.minY, 0);
    expect(data.maxY, 100);
    final spots = data.lineBarsData.single.spots;
    expect(spots.map((s) => s.x).toList(), [0.0, 1.0, 2.0]);
    expect(spots.map((s) => s.y).toList(), [78.0, 62.0, 73.0],
        reason: 'plotted points must equal the weekly DHS from the aggregates');

    // x-axis labels are the bucket labels
    expect(find.text('3 Aug'), findsOneWidget);
    expect(find.text('10 Aug'), findsOneWidget);
    expect(find.text('17 Aug'), findsOneWidget);

    // tier chips = sum of safe/caution/avoid across the 3 weeks (5 / 2 / 2)
    expect(_text(tester, const Key('tier-Safe-count')), '5');
    expect(_text(tester, const Key('tier-Caution-count')), '2');
    expect(_text(tester, const Key('tier-Avoid-count')), '2');

    expect(tester.takeException(), isNull);
  });

  testWidgets('Monthly toggle switches to the single monthly bucket', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();

    // one monthly point -> no line, a note instead; tier chips unchanged (5/2/2)
    expect(find.byType(LineChart), findsNothing);
    expect(find.textContaining('Not enough history yet for a monthly line.'),
        findsOneWidget);
    expect(_text(tester, const Key('tier-Safe-count')), '5');
    expect(_text(tester, const Key('tier-Caution-count')), '2');
    expect(_text(tester, const Key('tier-Avoid-count')), '2');
  });
}
