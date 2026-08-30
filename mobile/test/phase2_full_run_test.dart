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
import 'package:carecart/src/core/history_api.dart';
import 'package:carecart/src/core/notifications.dart';
import 'package:carecart/src/core/nudges_api.dart';
import 'package:carecart/src/features/trends/trends_screen.dart';
import 'package:carecart/src/core/widgets.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:carecart/src/state/onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

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

    final vault = FakeVaultApi()
      ..medications.addAll(const [
        (name: 'Telmisartan', dosage: '40 mg'),
        (name: 'Levothyroxine', dosage: '75 mcg'),
      ]);
    final history = HistoryLoaded(HistoryPage(
      total: 1,
      limit: 50,
      offset: 0,
      hasMore: false,
      items: [
        ScanHistoryEntry(
          id: '1',
          productName: 'Instant Masala Noodles',
          score: 24,
          tier: 'avoid',
          scannedAt: DateTime.now().toUtc(),
        ),
      ],
    ));

    final container = ProviderContainer(overrides: [
      ...fakeBackendOverrides(
        auth: FakeAuthApi(devCode: '424242'),
        vault: vault,
        history: history,
        trends: const TrendsLoaded(Trends(
            timezone: 'UTC', totalScans: 0, dietHealthScore: 0,
            deltaSevenDay: 0, trend: 'steady')),
        nudges: NudgesLoaded(NudgesPage(
          latestSeq: 1,
          items: [
            Nudge(
                id: 'n1',
                seq: 1,
                factor: 'sodium',
                hitCount: 3,
                windowDays: 14,
                createdAt: DateTime(2026, 8, 20),
                message: 'Sodium was flagged in 3 of your last 14 days of '
                    'scans. Try a low-sodium namkeen and rinse canned pulses.'),
          ],
        )),
      ),
      notificationServiceProvider.overrideWithValue(const NoopNotificationService()),
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
    await tester.enterText(find.byType(TextField).first, '98765 43210');
    await tester.tap(find.text('Continue'));
    await tester.pump(); // request-otp -> OTP screen
    expect(find.text('Enter the code'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1400)); // dev code stages in
    expect(onb().oOtp, '424242');
    await tester.tap(find.text('Verified — continue'));
    await tester.pumpAndSettle();
    _ok('onboarding: login → OTP (dev code) → token stored → steps');

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
      if (i == 0) {
        await tester.enterText(find.byType(TextField), 'Devi');
        await tester.pump();
        expect(onb().oName, 'Devi');
      }
      if (stepPick[i] != null) {
        await tester.tap(find.text(stepPick[i]!));
        await tester.pump();
      }
      await tester.tap(find.text(i == 5 ? 'Complete' : 'Next'));
      await tester.pumpAndSettle();
    }
    _ok('onboarding: walked all 6 profile steps');

    // building writes the profile to the vault (fakes here), then -> done
    expect(onb().oScreen, OnbScreen.done);
    expect(find.text("You're set up, Devi"), findsOneWidget);
    _ok('onboarding: profile written → done');

    await tester.pump(const Duration(milliseconds: 1600)); // auto-handoff
    await tester.pumpAndSettle();

    // ===================== HOME =====================
    expect(find.byType(MainAppShell), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsOneWidget, reason: 'nav on tab screen');
    expect(find.text('Good evening, Devi'), findsOneWidget);
    expect(find.text('Diet Health Score'), findsWidgets);
    expect(app().screen, MainScreen.home);
    noException('home');
    _ok('HOME — "Good evening, Devi", diet score card, nav visible');

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
    expect(find.textContaining('logged automatically'), findsOneWidget);
    expect(find.textContaining('TODAY'), findsWidgets); // day group from GET /history
    expect(find.text('Instant Masala Noodles'), findsWidgets);
    noException('history');
    _ok('HISTORY — "Food history", live GET /history rows, nav visible');

    await tester.tap(find.text('Meds'));
    await tester.pumpAndSettle();
    expect(find.byType(MedsScreen), findsOneWidget);
    expect(find.text('Medications'), findsOneWidget);
    expect(find.text('Each one changes what we flag on a label.'), findsOneWidget);
    expect(find.text('Telmisartan'), findsOneWidget);
    expect(find.text('Levothyroxine'), findsOneWidget);
    noException('meds');
    _ok('MEDS — live GET /me/medications cards, nav visible');

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    _ok('tabs — Home/Trend/History/Meds all reachable both ways');

    // ===================== SEARCH (food lookup) =====================
    await tester.tap(find.text('Look it up'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsNothing);
    expect(find.byKey(const Key('food-search-field')), findsOneWidget);
    expect(find.textContaining('Type a dish or product name'), findsOneWidget);
    noException('search');
    _ok('SEARCH — food-search field + idle hint, no nav');

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    _ok('SEARCH — back button returns to home (no dead-end)');

    // ===================== NUDGE =====================
    await tester.tap(find.text("What's driving it"));
    await tester.pumpAndSettle();
    expect(find.byType(NudgeScreen), findsOneWidget);
    expect(find.byType(CcBottomNav), findsNothing);
    // wired to GET /nudges (stubbed): heading from factor + the actionable message
    expect(tester.widget<Text>(find.byKey(const Key('nudge-heading'))).data,
        'Sodium keeps turning up in your scans');
    expect(find.text('ONE CHANGE TO TRY'), findsOneWidget);
    expect(find.textContaining('rinse canned pulses'), findsOneWidget);
    noException('nudge');
    _ok('NUDGE — real nudge (heading + one actionable change), no nav');

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    _ok('NUDGE — close (X) returns to home (no dead-end)');

    // ===================== PROFILE SHEET =====================
    await tester.tap(find.byKey(const Key('home-profile-button')));
    await tester.pumpAndSettle();
    expect(find.text('Who are we shopping for?'), findsOneWidget);
    expect(find.text('Each profile has its own medications and ceilings.'),
        findsOneWidget);
    // the "You" row now carries the name entered during onboarding
    expect(find.text('Devi'), findsOneWidget);
    expect(find.text('Sunita Deshmukh'), findsOneWidget);
    expect(find.text('Ira Deshmukh'), findsOneWidget);
    expect(app().showProfiles, isTrue);
    noException('profile sheet');
    _ok('PROFILE SHEET — self (named) + 2 family fixtures');

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
