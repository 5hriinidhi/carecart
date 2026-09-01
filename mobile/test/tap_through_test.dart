// Full tap-through of the real /app flow (MainAppShell + mainAppProvider):
//   home -> scan FAB -> scan -> pick product -> analyzing -> result
//        -> home (result close) -> Trend tab -> History tab
// plus a state-persistence check: scrolling Trends and leaving/returning keeps
// its scroll offset (IndexedStack keeps the tab mounted), and state keys
// (pid, step) are not reset by navigating.
//
//   flutter test test/tap_through_test.dart -r expanded

import 'package:carecart/src/core/widgets.dart';
import 'package:carecart/src/features/analyzing/analyzing_screen.dart';
import 'package:carecart/src/features/app_shell.dart';
import 'package:carecart/src/features/history/history_screen.dart';
import 'package:carecart/src/features/home/home_screen.dart';
import 'package:carecart/src/features/result/result_screen.dart';
import 'package:carecart/src/features/scan/scan_screen.dart';
import 'package:carecart/src/features/trends/trends_screen.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

void _step(String s) {
  // ignore: avoid_print
  print('  ▶ $s');
}

void main() {
  testWidgets('home → scan → analyzing → result → home → trends → history, state persists',
      (tester) async {
    tester.view.physicalSize = const Size(430, 908);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: fakeBackendOverrides(
        trends: sampleWeeklyTrends(),
        history: sampleHistory(),
      ),
    );
    addTearDown(container.dispose);
    MainAppState st() => container.read(mainAppProvider);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MainAppShell()),
    ));
    await tester.pump();

    // ---- 1. HOME ----
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsOneWidget, reason: 'nav visible on tab screens');
    expect(find.text('Good evening, Aarav'), findsOneWidget);
    expect(st().screen, MainScreen.home);
    expect(st().tab, MainScreen.home);
    _step('HOME: HomeScreen shown, bottom nav visible, tab=home');

    // ---- 2. tap the centre scan FAB ----
    final fab = find.descendant(
      of: find.byType(CcBottomNav),
      matching: find.byIcon(Icons.qr_code_scanner_rounded),
    );
    expect(fab, findsOneWidget);
    await tester.tap(fab);
    await tester.pump();
    _step('tapped scan FAB');

    // ---- 3. SCAN ----
    expect(find.byType(ScanScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsNothing, reason: 'nav hidden on scan');
    expect(find.text('Hold the barcode in the frame'), findsOneWidget);
    expect(st().screen, MainScreen.scan);
    expect(st().tab, MainScreen.home, reason: 'tab remembered while off a tab screen');
    _step('SCAN: dark scan screen, no bottom nav, tab still =home');

    // ---- 4. pick a demo product -> analyzing ----
    await tester.tap(find.text('Instant Masala Noodles'));
    await tester.pump();
    expect(find.byType(AnalyzingScreen), findsOneWidget);
    expect(find.text('Setting up your verdict'), findsOneWidget);
    expect(st().screen, MainScreen.analyzing);
    expect(st().pid, 'noodles');
    _step('ANALYZING: step=${st().step}, pid=noodles');

    // ---- 5. let the analyze timers run (4 x 550ms) ----
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
    _step('…timers advanced; step=${st().step}, screen=${st().screen.name}');

    // ---- 6. RESULT ----
    expect(find.byType(ResultScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsNothing, reason: 'nav hidden on result');
    // fixture rendered through the real POST /scan/verdict shape; tier from chipFor
    expect(tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data, 'Avoid');
    expect(tester.widget<Text>(find.byKey(const Key('verdict-score'))).data, '24');
    expect(st().screen, MainScreen.result);
    expect(st().pid, 'noodles');
    expect(st().step, 3, reason: 'analyze completed');
    _step('RESULT: tier "Avoid" (chipFor(24)), score 24, pid=noodles, step=3');

    // ---- 7. result close (X) -> HOME ----
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsOneWidget);
    expect(st().screen, MainScreen.home);
    // state keys survive the navigation
    expect(st().pid, 'noodles', reason: 'pid not reset by leaving result');
    expect(st().step, 3, reason: 'step not reset by leaving result');
    _step('HOME again via result close; pid & step preserved (${st().pid}, ${st().step})');

    // ---- 8. bottom nav -> TREND ----
    await tester.tap(find.text('Trend'));
    await tester.pump();
    expect(find.byType(TrendsScreen), findsOneWidget);
    expect(find.text('Your trend'), findsOneWidget);
    expect(st().screen, MainScreen.trends);
    expect(st().tab, MainScreen.trends);
    _step('TREND: TrendsScreen shown, tab=trends');

    // ---- 9. bottom nav -> HISTORY ----
    await tester.tap(find.text('History'));
    await tester.pump();
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('Food history'), findsOneWidget);

    // ---- 10. scroll History, leave, come back -> offset persists (IndexedStack) ----
    Finder historyScroll() => find.descendant(
          of: find.byType(HistoryScreen),
          matching: find.byType(Scrollable),
        );
    double historyOffset() =>
        tester.state<ScrollableState>(historyScroll()).position.pixels;

    await tester.drag(historyScroll(), const Offset(0, -320));
    await tester.pump();
    final offAfterScroll = historyOffset();
    expect(offAfterScroll, greaterThan(100));
    _step('scrolled History to offset ${offAfterScroll.toStringAsFixed(0)}');

    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pump();
    final offOnReturn = historyOffset();
    expect(offOnReturn, moreOrLessEquals(offAfterScroll, epsilon: 1),
        reason: 'History scroll position must persist across tab switches');
    expect(st().screen, MainScreen.history);
    expect(st().tab, MainScreen.history);
    _step('HISTORY: HistoryScreen shown, tab=history');

    _step('DONE — full tap-through passed');
  });
}
