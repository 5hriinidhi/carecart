// Phase 2 Check — one continuous run through the whole prototype recreation,
// from a cold launch, via the REAL router:
//
//   onboarding (login → OTP → all 6 profile steps → building → done)
//     → home → scan → analyzing → result → home
//     → trends → history → meds  (bottom-nav tabs)
//     → search → home
//     → nudge → home
//     → profile sheet → home
//
// Asserts each screen renders its prototype copy (not placeholder text), that
// the bottom nav shows only on the 4 tab screens, and that every non-tab
// screen has a working way back (no dead-ends). Fails on any layout exception.
//
//   flutter test test/phase2_full_run_test.dart -r expanded

import 'package:carecart/src/app.dart';
import 'package:carecart/src/features/analyzing/analyzing_screen.dart';
import 'package:carecart/src/features/app_shell.dart';
import 'package:carecart/src/features/history/history_screen.dart';
import 'package:carecart/src/features/home/home_screen.dart';
import 'package:carecart/src/features/meds/meds_screen.dart';
import 'package:carecart/src/features/nudge/nudge_screen.dart';
import 'package:carecart/src/features/result/result_screen.dart';
import 'package:carecart/src/features/scan/scan_screen.dart';
import 'package:carecart/src/features/search/search_screen.dart';
import 'package:carecart/src/core/analytics_api.dart';
import 'package:carecart/src/features/trends/trends_screen.dart';
import 'package:carecart/src/core/widgets.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:carecart/src/state/onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void _ok(String s) {
  // ignore: avoid_print
  print('  ✓ $s');
}

void main() {
  testWidgets('full prototype run: onboarding → 9 screens → profile sheet → home',
      (tester) async {
    tester.view.physicalSize = const Size(430, 940);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      trendsProvider.overrideWith((ref) async => const TrendsLoaded(Trends(
          timezone: 'UTC', totalScans: 0, dietHealthScore: 0,
          deltaSevenDay: 0, trend: 'steady'))),
    ]);
    addTearDown(container.dispose);
    OnboardingState onb() => container.read(onboardingFlowProvider);
    MainAppState app() => container.read(mainAppProvider);

    void noException(String where) =>
        expect(tester.takeException(), isNull, reason: 'exception at: $where');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CareCartApp(),
    ));
    await tester.pumpAndSettle();

    // ===================== ONBOARDING =====================
    expect(find.text('CareCart'), findsOneWidget);
    expect(onb().oScreen, OnbScreen.login);
    await tester.enterText(find.byType(TextField), '98765 43210');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the code'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1800)); // fake OTP autofill
    expect(onb().oOtp, '4192');
    await tester.tap(find.text('Verified — continue'));
    await tester.pumpAndSettle();
    _ok('onboarding: login → OTP (auto-filled) → steps');

    const stepTitles = [
      'A few things about you',
      'How active is a normal week?',
      'Your measurements',
      'Any dietary preferences?',
      'Anything you must avoid?',
      'What are you taking?',
    ];
    const stepPick = {0: 'Male', 1: 'Sedentary', 3: 'Low sugar', 4: 'Dairy', 5: 'Type it in'};
    for (var i = 0; i < 6; i++) {
      expect(onb().oScreen, OnbScreen.steps);
      expect(onb().oStep, i);
      expect(find.text(stepTitles[i]), findsOneWidget, reason: 'step ${i + 1} copy');
      noException('onboarding step ${i + 1}');
      if (stepPick[i] != null) {
        await tester.tap(find.text(stepPick[i]!));
        await tester.pump();
      }
      await tester.tap(find.text(i == 5 ? 'Complete' : 'Next'));
      if (i == 5) {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }
    }
    _ok('onboarding: walked all 6 profile steps');

    expect(onb().oScreen, OnbScreen.building);
    expect(find.text('Building your profile'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2700)); // fake build progression
    expect(onb().oScreen, OnbScreen.done);
    expect(find.text("You're set up, Aarav"), findsOneWidget);
    _ok('onboarding: building → done');

    await tester.pump(const Duration(milliseconds: 1600)); // auto-handoff
    await tester.pumpAndSettle();

    // ===================== HOME =====================
    expect(find.byType(MainAppShell), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsOneWidget, reason: 'nav on tab screen');
    expect(find.text('Good evening, Aarav'), findsOneWidget);
    expect(find.text('Diet Health Score'), findsWidgets);
    expect(app().screen, MainScreen.home);
    noException('home');
    _ok('HOME — "Good evening, Aarav", diet score card, nav visible');

    // ===================== SCAN (via FAB) =====================
    await tester.tap(find.descendant(
      of: find.byType(CcBottomNav),
      matching: find.byIcon(Icons.qr_code_scanner_rounded),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ScanScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsNothing, reason: 'nav hidden on scan');
    expect(find.text('Hold the barcode in the frame'), findsOneWidget);
    expect(find.text('DEMO — PICK A PRODUCT TO SCAN'), findsOneWidget);
    noException('scan');
    _ok('SCAN — dark viewfinder, demo picker, no nav');

    // back affordance works (no dead-end)
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    _ok('SCAN — back button returns to home (no dead-end)');

    // ===================== SCAN → ANALYZING → RESULT =====================
    await tester.tap(find.descendant(
      of: find.byType(CcBottomNav),
      matching: find.byIcon(Icons.qr_code_scanner_rounded),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instant Masala Noodles'));
    await tester.pump();
    expect(find.byType(AnalyzingScreen), findsOneWidget);
    expect(find.text('Setting up your verdict'), findsOneWidget);
    expect(find.text('This stays on your phone.'), findsOneWidget);
    noException('analyzing');
    _ok('ANALYZING — spinner + 4 steps, "Setting up your verdict"');

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
    expect(find.byType(ResultScreen), findsOneWidget);
    expect(app().screen, MainScreen.result);
    // the fixture is now adapted into the real POST /scan/verdict shape:
    // score + tier (from chipFor) + reasons.
    expect(tester.widget<Text>(find.byKey(const Key('verdict-score'))).data, '24');
    expect(tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data, 'Avoid');
    expect(find.textContaining('CARECART SCORE'), findsOneWidget);
    expect(find.text('Why this verdict'), findsOneWidget);
    expect(find.text('Maltodextrin'), findsOneWidget); // fixture flag -> reason title
    expect(find.byType(CcBottomNav), findsNothing, reason: 'nav hidden on result');
    noException('result');
    _ok('RESULT — score 24 -> tier "Avoid" via chipFor(), fixture flags as reasons, no nav');

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    _ok('RESULT — close (X) returns to home (no dead-end)');

    // ===================== TABS: TRENDS / HISTORY / MEDS =====================
    await tester.tap(find.text('Trend'));
    await tester.pumpAndSettle();
    expect(find.byType(TrendsScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsOneWidget);
    expect(find.text('Your trend'), findsOneWidget);
    // Diet Health Score card is wired to GET /analytics/trends (stubbed empty here)
    expect(find.text('Built from 0 scans. No manual logging.'), findsOneWidget);
    expect(find.textContaining('Diet Health Score and weekly trend'), findsOneWidget);
    expect(find.text('Nutrient trajectories'), findsOneWidget);
    expect(find.text('Sodium'), findsWidgets); // trajectory fixture (separate feature)
    noException('trends');
    _ok('TRENDS — "Your trend", live score card (empty state), trajectories, nav');

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('Food history'), findsOneWidget);
    expect(find.text('Every scan is kept locally. Export or wipe it any time.'),
        findsOneWidget);
    expect(find.textContaining('TODAY · 24 AUG'), findsWidgets);
    noException('history');
    _ok('HISTORY — "Food history", day groups from fixtures, nav visible');

    await tester.tap(find.text('Meds'));
    await tester.pumpAndSettle();
    expect(find.byType(MedsScreen), findsOneWidget);
    expect(find.text('Medications'), findsOneWidget);
    expect(find.text('Each one changes what we flag on a label.'), findsOneWidget);
    expect(find.text('Telmisartan'), findsOneWidget);
    expect(find.text('Levothyroxine'), findsOneWidget);
    expect(find.text('Conditions on file'), findsOneWidget);
    noException('meds');
    _ok('MEDS — 4 medication cards + conditions, nav visible');

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    _ok('tabs — Home/Trend/History/Meds all reachable both ways');

    // ===================== SEARCH =====================
    await tester.tap(find.text('Look it up'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsNothing);
    expect(find.text('RECENTLY SCANNED NEAR YOU'), findsOneWidget);
    expect(find.text('Roasted Chana, Lightly Salted'), findsOneWidget); // fixture
    noException('search');
    _ok('SEARCH — recent list from fixtures, no nav');

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    _ok('SEARCH — back button returns to home (no dead-end)');

    // ===================== NUDGE =====================
    await tester.tap(find.text("What's driving it"));
    await tester.pumpAndSettle();
    expect(find.byType(NudgeScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsNothing);
    expect(find.text('Sodium is creeping up on your weekday lunches'), findsOneWidget);
    expect(find.text('The three scans behind this'), findsOneWidget);
    expect(find.text('ONE CHANGE TO TRY'), findsOneWidget);
    noException('nudge');
    _ok('NUDGE — full check-in copy + 3 scans + "one change", no nav');

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    _ok('NUDGE — close (X) returns to home (no dead-end)');

    // ===================== PROFILE SHEET =====================
    await tester.tap(find.descendant(
      of: find.byType(HomeScreen),
      matching: find.text('A'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Who are we shopping for?'), findsOneWidget);
    expect(find.text('Each profile has its own medications and ceilings.'),
        findsOneWidget);
    expect(find.text('Aarav Deshmukh'), findsOneWidget);
    expect(find.text('Sunita Deshmukh'), findsOneWidget);
    expect(find.text('Ira Deshmukh'), findsOneWidget);
    expect(app().showProfiles, isTrue);
    noException('profile sheet');
    _ok('PROFILE SHEET — 3 profiles from fixtures');

    await tester.tapAt(const Offset(10, 10)); // tap the scrim
    await tester.pumpAndSettle();
    expect(find.text('Who are we shopping for?'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(app().showProfiles, isFalse);
    _ok('PROFILE SHEET — scrim tap dismisses back to home (no dead-end)');

    // ===================== END =====================
    expect(app().screen, MainScreen.home);
    noException('final');
    _ok('END — back at home, every screen visited, no dead-ends, no exceptions');
  });
}
