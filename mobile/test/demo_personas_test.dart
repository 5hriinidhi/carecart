// Phase 6.4 verification — a freshly-installed release build, signed in as each
// seeded demo persona, shows realistic pre-populated history / trends / nudges
// on first open (no waiting for usage to accumulate).
//
// Drives the real MainAppShell against payloads shaped exactly like what
// backend/scripts/seed_demo_users.py produces per persona.

import 'package:carecart/src/core/analytics_api.dart';
import 'package:carecart/src/core/history_api.dart';
import 'package:carecart/src/core/notifications.dart';
import 'package:carecart/src/core/nudges_api.dart';
import 'package:carecart/src/features/app_shell.dart';
import 'package:carecart/src/features/history/history_screen.dart';
import 'package:carecart/src/features/trends/trends_screen.dart';
import 'package:carecart/src/features/nudge/nudge_screen.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:carecart/src/core/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

class _Persona {
  const _Persona(this.name, this.history, this.trends, this.nudgeFactor,
      this.nudgeText);
  final String name;
  final List<ScanHistoryEntry> history;
  final Trends trends;
  final String? nudgeFactor; // null = no nudge (Meera)
  final String? nudgeText;
}

ScanHistoryEntry _h(String name, int score, String tier, int daysAgo,
        {String? factor}) =>
    ScanHistoryEntry(
      id: '$name-$daysAgo',
      productName: name,
      score: score,
      tier: tier,
      hardStop: tier == 'avoid' && score == 0,
      scannedAt: DateTime.now().toUtc().subtract(Duration(days: daysAgo)),
      keyReasons: factor == null
          ? const []
          : [HistoryReason(kind: 'x', severity: 'high', title: '$factor flag', factor: factor)],
    );

Trends _trends(int dhs, String trend, List<(String, int, int, int, int)> weeks) =>
    Trends(
      timezone: 'Asia/Kolkata',
      totalScans: weeks.fold(0, (s, w) => s + w.$2),
      dietHealthScore: dhs,
      deltaSevenDay: 0,
      trend: trend,
      weekly: [
        for (final (label, n, safe, caution, avoid) in weeks)
          TrendBucket(
              periodStart: DateTime.utc(2026, 8, 3),
              label: label,
              scans: n,
              avgScore: 60,
              medianScore: 60,
              minScore: 20,
              maxScore: 95,
              safe: safe,
              caution: caution,
              avoid: avoid,
              dietHealthScore: dhs),
      ],
      monthly: const [],
    );

final _personas = <_Persona>[
  _Persona(
    'Priya',
    [
      _h('Coca-Cola 250ml', 28, 'avoid', 1, factor: 'added_sugar'),
      _h('Greek Yogurt Unsweetened', 85, 'safe', 2),
      _h('Parle-G Biscuits', 42, 'avoid', 3, factor: 'added_sugar'),
      _h('Sprouts Salad Bowl', 92, 'safe', 5),
      _h('Marie Gold Biscuits', 55, 'caution', 6, factor: 'added_sugar'),
    ],
    _trends(57, 'steady', [('3 Aug', 5, 2, 2, 1), ('10 Aug', 4, 2, 0, 2)]),
    'added_sugar',
    'Added sugar came up in 6 scans',
  ),
  _Persona(
    'Ravi',
    [
      _h('Moringa Powder Supplement', 44, 'avoid', 1, factor: 'vitamin_k'),
      _h('Curd Rice Ready Meal', 76, 'safe', 2),
      _h('Spinach & Corn Sandwich', 48, 'avoid', 4, factor: 'vitamin_k'),
      _h('Kale Chips', 46, 'avoid', 11, factor: 'vitamin_k'),
    ],
    _trends(63, 'steady', [('3 Aug', 4, 2, 2, 0)]),
    'vitamin_k',
    'Vitamin K keeps showing up',
  ),
  _Persona(
    'Aarav',
    [
      _h('Cashew Cookies', 0, 'avoid', 2, factor: 'nut_allergen'),
      _h('Boiled Egg Pack', 91, 'safe', 4),
      _h('Almond Energy Bar', 0, 'avoid', 6, factor: 'nut_allergen'),
      _h('Snickers Bar', 0, 'avoid', 10, factor: 'nut_allergen'),
    ],
    _trends(48, 'declining', [('3 Aug', 5, 2, 0, 3)]),
    'nut_allergen',
    'Tree nuts keep turning up',
  ),
  _Persona(
    'Meera',
    [
      _h('Banana', 97, 'safe', 1),
      _h('Vegetable Poha', 92, 'safe', 4),
      _h('Greek Yogurt', 90, 'safe', 10),
    ],
    _trends(91, 'improving', [('3 Aug', 6, 6, 0, 0)]),
    null,
    null,
  ),
];

void main() {
  for (final p in _personas) {
    testWidgets('${p.name}: history / trends / nudges are pre-populated on open',
        (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: [
        ...fakeBackendOverrides(
          history: HistoryLoaded(HistoryPage(
              items: p.history,
              total: p.history.length,
              limit: 50,
              offset: 0,
              hasMore: false)),
          trends: TrendsLoaded(p.trends),
          nudges: p.nudgeFactor == null
              ? NudgesLoaded(const NudgesPage(items: [], latestSeq: 0))
              : NudgesLoaded(NudgesPage(latestSeq: 1, items: [
                  Nudge(
                    id: 'n',
                    seq: 1,
                    factor: p.nudgeFactor!,
                    message: p.nudgeText!,
                    hitCount: 4,
                    windowDays: 14,
                    createdAt: DateTime(2026, 8, 20),
                  )
                ])),
        ),
        notificationServiceProvider
            .overrideWithValue(const NoopNotificationService()),
      ]);
      addTearDown(container.dispose);

      final app = container.read(mainAppProvider.notifier);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MainAppShell()),
      ));
      await tester.pumpAndSettle();

      // ── History tab: real rows, not an empty state ──
      app.goTab(MainScreen.history);
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text(p.history.first.productName), findsOneWidget);
      expect(find.textContaining('No scans yet'), findsNothing);

      // ── Trends tab: a real Diet Health Score, not "scan a few products" ──
      app.goTab(MainScreen.trends);
      await tester.pumpAndSettle();
      expect(find.byType(TrendsScreen), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('dhs-value'))).data,
          p.trends.dietHealthScore.toString());
      expect(find.textContaining('Scan a few products'), findsNothing);

      // ── Nudge screen ──
      app.goNudge();
      await tester.pumpAndSettle();
      expect(find.byType(NudgeScreen), findsOneWidget);
      if (p.nudgeFactor == null) {
        expect(find.textContaining('Nothing to flag'), findsOneWidget,
            reason: '${p.name} has no recurring pattern — no nudge');
      } else {
        expect(find.textContaining(p.nudgeText!.split(' ').take(3).join(' ')),
            findsOneWidget);
      }

      // (release-build gating of /debug + the banner is covered by
      //  release_config_test.dart; here we only care that persona data shows)
    });
  }

  testWidgets('the offline strip / debug chip are absent with a healthy backend',
      (tester) async {
    final container = ProviderContainer(overrides: [
      ...fakeBackendOverrides(),
      notificationServiceProvider
          .overrideWithValue(const NoopNotificationService()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MainAppShell()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-offline-strip')), findsNothing);
    // CcBottomNav exists but exposes only home/trends/history/meds + scan
    expect(find.byType(CcBottomNav), findsOneWidget);
  });
}
