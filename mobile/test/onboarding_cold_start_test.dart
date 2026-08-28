// Cold app start -> full onboarding -> handoff to the main app, driven through
// the REAL router (routerProvider + the onboarding gate/redirect).
//
// Verifies at every step that:
//   * onboardingFlowProvider.oScreen / oStep advance correctly
//   * the fake OTP timer fills the code and the flow progresses
//   * mainAppProvider.screen / tab are NEVER touched (stay home/home) and the
//     MainAppShell is not mounted until the final handoff
//
//   flutter test test/onboarding_cold_start_test.dart -r expanded

import 'package:carecart/src/app.dart';
import 'package:carecart/src/features/app_shell.dart';
import 'package:carecart/src/features/home/home_screen.dart';
import 'package:carecart/src/features/onboarding/onboarding_screen.dart';
import 'package:carecart/src/routing/app_router.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:carecart/src/state/onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void _step(String s) {
  // ignore: avoid_print
  print('  ▶ $s');
}

void main() {
  testWidgets('cold start → login → OTP → 6 steps → building → done → home',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    OnboardingState onb() => container.read(onboardingFlowProvider);
    MainAppState main() => container.read(mainAppProvider);
    bool gate() => container.read(onboardingCompleteProvider);

    // The main-app machine must not move off its defaults until the handoff.
    void assertMainUntouched(String where) {
      expect(main().screen, MainScreen.home, reason: 'main.screen moved at: $where');
      expect(main().tab, MainScreen.home, reason: 'main.tab moved at: $where');
      expect(gate(), isFalse, reason: 'router gate flipped early at: $where');
      expect(find.byType(MainAppShell), findsNothing,
          reason: 'MainAppShell mounted early at: $where');
    }

    // ---- cold start ----
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CareCartApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('CareCart'), findsOneWidget);
    expect(onb().oScreen, OnbScreen.login);
    expect(onb().oStep, 0);
    assertMainUntouched('login');
    _step('COLD START → redirected to /onboarding, oScreen=login, oStep=0');

    // ---- enter a fake phone number ----
    await tester.enterText(find.byType(TextField), '98765 43210');
    await tester.pump();
    expect(onb().oPhone, '98765 43210');
    _step('typed phone "98765 43210" → oPhone updated');

    // ---- Continue → OTP screen ----
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(onb().oScreen, OnbScreen.otp);
    expect(find.text('Enter the code'), findsOneWidget);
    expect(onb().oOtp, '');
    assertMainUntouched('otp (just arrived)');
    _step('tapped Continue → oScreen=otp, oOtp="" ');

    // ---- fake OTP timer fills the code, then it auto-progresses on continue ----
    await tester.pump(const Duration(milliseconds: 1800));
    expect(onb().oOtp, '4192');
    expect(onb().otpComplete, isTrue);
    _step('fake timer filled oOtp="4192" (otpComplete=true)');

    await tester.tap(find.text('Verified — continue'));
    await tester.pumpAndSettle();
    expect(onb().oScreen, OnbScreen.steps);
    expect(onb().oStep, 0);
    assertMainUntouched('steps/0');
    _step('code accepted → oScreen=steps, oStep=0');

    // ---- walk all 6 profile steps ----
    const titles = <int, String>{
      0: 'A few things about you',
      1: 'How active is a normal week?',
      2: 'Your measurements',
      3: 'Any dietary preferences?',
      4: 'Anything you must avoid?',
      5: 'What are you taking?',
    };
    const pickPerStep = <int, String>{
      0: 'Male',
      1: 'Sedentary',
      3: 'Low sugar',
      4: 'Dairy',
      5: 'Type it in',
    };

    for (var i = 0; i < 6; i++) {
      expect(onb().oScreen, OnbScreen.steps, reason: 'step $i screen');
      expect(onb().oStep, i, reason: 'step $i index');
      expect(onb().oStepKind, kOnbSteps[i], reason: 'step $i kind');
      expect(find.text(titles[i]!), findsOneWidget, reason: 'step $i title');
      assertMainUntouched('steps/$i');

      final pick = pickPerStep[i];
      if (pick != null) {
        await tester.tap(find.text(pick));
        await tester.pump();
      }

      await tester.tap(find.text(i == 5 ? 'Complete' : 'Next'));
      // don't pumpAndSettle past step 6 — the building screen spins forever
      if (i == 5) {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }
      _step('STEP ${i + 1}/6 "${titles[i]}"'
          '${pick != null ? '  (picked "$pick")' : ''} → '
          '${i == 5 ? 'Complete' : 'Next'}');
    }

    // ---- building ----
    expect(onb().oScreen, OnbScreen.building);
    expect(onb().oBuild, 0);
    expect(find.text('Building your profile'), findsOneWidget);
    assertMainUntouched('building');
    _step('oScreen=building, oBuild=0');

    // fake progression: oBuild 1/2/3 @ 700/1350/1950ms, done @ 2600ms
    await tester.pump(const Duration(milliseconds: 800));
    expect(onb().oBuild, 1);
    await tester.pump(const Duration(milliseconds: 1200)); // ~2000ms
    expect(onb().oBuild, 3);
    await tester.pump(const Duration(milliseconds: 700)); // ~2700ms
    expect(onb().oScreen, OnbScreen.done);
    expect(find.text("You're set up, Aarav"), findsOneWidget);
    assertMainUntouched('done (pre-handoff)');
    _step('fake timers → oBuild 1→3 → oScreen=done; main app STILL untouched');

    // ---- handoff: auto-fires ~1500ms after reaching done ----
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();

    expect(gate(), isTrue, reason: 'onboarding gate flipped at handoff');
    expect(find.byType(MainAppShell), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(main().screen, MainScreen.home);
    expect(main().tab, MainScreen.home);
    // the onboarding machine keeps its own final state, untouched
    expect(onb().oScreen, OnbScreen.done);
    _step('HANDOFF → /app: MainAppShell + HomeScreen, main.screen=home, '
        'main.tab=home; onboarding machine still oScreen=done');
    _step('DONE — full cold-start sequence verified');
  });
}
