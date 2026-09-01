// Full tap-through of the onboarding UI (OnboardingScreen + onboardingFlowProvider):
//   login -> phone -> OTP (dev code) -> gender -> activity -> body -> diet
//         -> allergies -> meds (scan Rx) -> Complete -> building (real vault
//         writes, against fakes) -> done -> hands off
//
//   flutter test test/onboarding_tap_through_test.dart -r expanded

import 'package:carecart/src/core/drugs_api.dart';
import 'package:carecart/src/features/onboarding/onboarding_screen.dart';
import 'package:carecart/src/state/onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

void _step(String s) {
  // ignore: avoid_print
  print('  ▶ $s');
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, '9876543210');
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pump(); // request-otp resolves -> OTP screen
  await tester.pump(const Duration(milliseconds: 1400)); // dev code stages in
  await tester.tap(find.text('Verified — continue'));
  await tester.pumpAndSettle(); // verify-otp -> steps
}

void main() {
  testWidgets('sign-in -> 6 steps -> building -> done -> onComplete fires',
      (tester) async {
    tester.view.physicalSize = const Size(430, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
        overrides: fakeBackendOverrides(
      auth: FakeAuthApi(devCode: '424242'),
      drugs: FakeDrugsApi(hits: const [
        DrugHit(name: 'Telmisartan 40 Tablet', saltComposition: 'Telmisartan (40mg)'),
        DrugHit(name: 'Metformin 500 Tablet', saltComposition: 'Metformin (500mg)'),
      ]),
    ));
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

    expect(find.text('CareCart'), findsOneWidget);
    expect(st().oScreen, OnbScreen.login);
    _step('LOGIN shown');

    await _signIn(tester);
    expect(st().oScreen, OnbScreen.steps);
    expect(st().oStepKind, OnbStep.gender);
    expect(find.text('A few things about you'), findsOneWidget);
    _step('signed in -> STEP 1 gender');

    await tester.enterText(find.byType(TextField), 'Kiran');
    await tester.pump();
    expect(st().oName, 'Kiran');
    _step('STEP 1 name = Kiran');

    await tester.tap(find.text('Female'));
    await tester.pump();
    expect(st().oGender, 'Female');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('How many days a week are you active?'), findsOneWidget);
    await tester.tap(find.text('4 days'));
    await tester.pump();
    expect(st().oExerciseDays, 4);
    _step('STEP 2 exercise = 4 days');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Your measurements'), findsOneWidget);
    _step('STEP 3 body');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Any dietary preferences?'), findsOneWidget);
    await tester.tap(find.text('High protein'));
    await tester.pump();
    expect(st().oDiet, contains('High protein'));
    _step('STEP 4 diet = High protein');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Anything you must avoid?'), findsOneWidget);
    _step('STEP 5 allergies');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('What are you taking?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'telmi');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Telmisartan 40 Tablet'));
    await tester.pump();
    expect(st().oRx.map((r) => r.name), const ['Telmisartan 40 Tablet']);
    _step('STEP 6 meds: added Telmisartan from search');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('A little about your lifestyle'), findsOneWidget);
    await tester.tap(find.text('Daily')); // smoking
    await tester.pump();
    await tester.tap(find.text('3')); // stress
    await tester.pump();
    _step('STEP 7 lifestyle');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Set a PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '4271');
    await tester.enterText(find.byType(TextField).at(1), '4271');
    await tester.pump();
    expect(st().oPinReady, isTrue);
    _step('STEP 8 PIN set');

    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle(); // building -> real vault writes -> done
    expect(st().oScreen, OnbScreen.done);
    expect(find.text("You're set up, Kiran"), findsOneWidget);
    expect(find.text('Female'), findsWidgets); // in the profile summary
    _step('DONE — summary rendered, greets by the name entered');

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

    final container = ProviderContainer(
        overrides: fakeBackendOverrides(auth: FakeAuthApi(devCode: '424242')));
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

    await _signIn(tester);
    for (var i = 0; i < kOnbSteps.length; i++) {
      await flow.next();
    }
    await tester.pumpAndSettle();
    expect(st().oScreen, OnbScreen.done);

    await tester.ensureVisible(find.text('First scan, right now'));
    await tester.tap(find.text('First scan, right now'));
    await tester.pump();
    expect(completeCalls, greaterThanOrEqualTo(1));

    await tester.ensureVisible(find.text('Run the walkthrough again'));
    await tester.tap(find.text('Run the walkthrough again'));
    await tester.pumpAndSettle();
    expect(st().oScreen, OnbScreen.login);

    // drain the pending auto-handoff timer from reaching done earlier
    await tester.pump(const Duration(milliseconds: 1600));
  });
}
