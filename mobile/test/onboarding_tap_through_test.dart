// Full tap-through of the onboarding UI (OnboardingScreen + onboardingFlowProvider):
//   login -> (skip auth) -> gender -> activity -> body -> diet -> allergies
//         -> meds (scan Rx) -> Complete -> building -> done -> hands off
//
//   flutter test test/onboarding_tap_through_test.dart -r expanded

import 'package:carecart/src/features/onboarding/onboarding_screen.dart';
import 'package:carecart/src/state/onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void _step(String s) {
  // ignore: avoid_print
  print('  ▶ $s');
}

void main() {
  testWidgets('sign-in -> 6 steps -> building -> done -> onComplete fires',
      (tester) async {
    tester.view.physicalSize = const Size(430, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    OnboardingState st() => container.read(onboardingFlowProvider);

    var completeCalls = 0;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: OnboardingScreen(onComplete: () => completeCalls++),
      ),
    ));
    await tester.pump();

    // ---- login ----
    expect(find.text('CareCart'), findsOneWidget);
    expect(st().oScreen, OnbScreen.login);
    _step('LOGIN shown');

    await tester.tap(find.text('Continue with Apple'));
    await tester.pump();
    expect(st().oScreen, OnbScreen.steps);
    expect(st().oStepKind, OnbStep.gender);
    expect(find.text('A few things about you'), findsOneWidget);
    _step('skipped auth -> STEP 1 gender');

    await tester.tap(find.text('Female'));
    await tester.pump();
    expect(st().oGender, 'Female');

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('How active is a normal week?'), findsOneWidget);
    await tester.tap(find.text('Moderate'));
    await tester.pump();
    expect(st().oActivity, 'Moderate');
    _step('STEP 2 activity = Moderate');

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Your measurements'), findsOneWidget);
    _step('STEP 3 body');

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Any dietary preferences?'), findsOneWidget);
    await tester.tap(find.text('High protein'));
    await tester.pump();
    expect(st().oDiet, contains('High protein'));
    _step('STEP 4 diet = High protein');

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Anything you must avoid?'), findsOneWidget);
    _step('STEP 5 allergies');

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('What are you taking?'), findsOneWidget);
    await tester.tap(find.text('Scan prescription'));
    await tester.pump();
    expect(find.text('Telmisartan'), findsOneWidget);
    expect(st().oRx, hasLength(2));
    _step('STEP 6 meds: scanned 2 prescriptions');

    // last step -> Complete -> building
    await tester.tap(find.text('Complete'));
    await tester.pump();
    expect(st().oScreen, OnbScreen.building);
    expect(find.text('Building your profile'), findsOneWidget);
    _step('BUILDING…');

    // fake progression: oBuild 1/2/3 @ 700/1350/1950, done @ 2600
    await tester.pump(const Duration(milliseconds: 2700));
    expect(st().oScreen, OnbScreen.done);
    expect(find.text("You're set up, Aarav"), findsOneWidget);
    expect(find.text('Female'), findsWidgets); // in the profile summary
    _step('DONE — summary rendered');

    // onComplete fires ~1500ms after reaching done (hand-off to /app)
    expect(completeCalls, 0);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(completeCalls, 1);
    _step('onComplete() fired — control handed to the main app');
  });

  testWidgets('done screen CTA hands off immediately; restart resets',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final flow = container.read(onboardingFlowProvider.notifier);
    OnboardingState st() => container.read(onboardingFlowProvider);

    var completeCalls = 0;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: OnboardingScreen(onComplete: () => completeCalls++),
      ),
    ));

    // jump the machine to done
    flow.skipAuth();
    for (var i = 0; i < 6; i++) {
      flow.next();
    }
    await tester.pump(const Duration(milliseconds: 2700));
    expect(st().oScreen, OnbScreen.done);

    await tester.ensureVisible(find.text('First scan, right now'));
    await tester.tap(find.text('First scan, right now'));
    await tester.pump();
    expect(completeCalls, greaterThanOrEqualTo(1));

    await tester.ensureVisible(find.text('Run the walkthrough again'));
    await tester.tap(find.text('Run the walkthrough again'));
    await tester.pump();
    expect(st().oScreen, OnbScreen.login);

    // drain the pending auto-handoff timer from reaching done earlier
    await tester.pump(const Duration(milliseconds: 1600));
  });
}
