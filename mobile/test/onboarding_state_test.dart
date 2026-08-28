// The onboarding state machine (the `o*`-prefixed keys, turn 2a of the
// prototype). Covers login -> otp -> 6 steps -> building -> done, the faked
// timer async, and that it never touches the main-app machine or the router
// gate.

import 'package:carecart/src/routing/app_router.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:carecart/src/state/onboarding_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer c;
  OnboardingFlow flow() => c.read(onboardingFlowProvider.notifier);
  OnboardingState st() => c.read(onboardingFlowProvider);

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('defaults mirror the prototype o* keys', () {
    final s = st();
    expect(s.oScreen, OnbScreen.login);
    expect(s.oStep, 0);
    expect(s.oPhone, '');
    expect(s.oOtp, '');
    expect(s.oGender, isNull);
    expect(s.oActivity, isNull);
    expect(s.oUnitW, 'KG');
    expect(s.oUnitH, 'cm');
    expect(s.oDiet, isEmpty);
    expect(s.oAllergy, isEmpty);
    expect(s.oRx, isEmpty);
    expect(s.oBuild, 0);
    expect(s.oPhoneShown, '98765 43210');
  });

  test('skipAuth jumps straight to the first profile step', () {
    flow().skipAuth();
    expect(st().oScreen, OnbScreen.steps);
    expect(st().oStep, 0);
    expect(st().oStepKind, OnbStep.gender);
  });

  test('next walks the 6 steps in order, then enters building', () {
    flow().skipAuth();
    final seen = <OnbStep>[st().oStepKind];
    for (var i = 0; i < 5; i++) {
      flow().next();
      seen.add(st().oStepKind);
    }
    expect(seen, const [
      OnbStep.gender,
      OnbStep.activity,
      OnbStep.body,
      OnbStep.diet,
      OnbStep.allergies,
      OnbStep.meds,
    ]);
    expect(st().oScreen, OnbScreen.steps);
    flow().next();
    expect(st().oScreen, OnbScreen.building);
  });

  test('back: first step and the OTP screen both return to login', () {
    flow().skipAuth();
    flow().next();
    expect(st().oStep, 1);
    flow().back();
    expect(st().oStep, 0);
    flow().back();
    expect(st().oScreen, OnbScreen.login);

    flow().submitPhone();
    expect(st().oScreen, OnbScreen.otp);
    flow().back(); // also cancels the pending fake-OTP timers
    expect(st().oScreen, OnbScreen.login);
    expect(st().oOtp, '');
  });

  test('verifyOtp is a no-op until all 4 digits are present', () {
    flow().submitPhone();
    expect(st().otpComplete, isFalse);
    flow().verifyOtp();
    expect(st().oScreen, OnbScreen.otp, reason: 'still waiting for the code');
    flow().back();
  });

  test('gender and activity are single-select', () {
    flow().skipAuth();
    flow().setGender('Male');
    flow().setGender('Female');
    expect(st().oGender, 'Female');
    flow().next();
    flow().setActivity('Moderate');
    expect(st().oActivity, 'Moderate');
  });

  test('diet / allergy toggle in and out; body fields update', () {
    flow().skipAuth();
    flow().toggleDiet('Low sodium');
    flow().toggleDiet('Vegan');
    flow().toggleDiet('Low sodium');
    expect(st().oDiet, const ['Vegan']);
    flow().toggleAllergy('Peanuts');
    expect(st().oAllergy, const ['Peanuts']);
    flow().setOther('mustard');
    flow().setUnitW('Lb');
    flow().setUnitH('inch');
    flow().setWeight('70');
    flow().setHeight('180');
    final s = st();
    expect(s.oUnitW, 'Lb');
    expect(s.oUnitH, 'inch');
    expect(s.oWeight, '70');
    expect(s.oHeight, '180');
    expect(s.oOther, 'mustard');
  });

  test('scanRx / addRx / removeRx manage the prescription list', () {
    flow().scanRx();
    expect(st().oRx.map((r) => r.name), const ['Telmisartan', 'Metformin']);
    flow().addRx();
    expect(st().oRx.map((r) => r.name),
        const ['Telmisartan', 'Metformin', 'Atorvastatin']);
    flow().removeRx(1);
    expect(st().oRx.map((r) => r.name), const ['Telmisartan', 'Atorvastatin']);
  });

  test('summaryRows reflects the collected profile', () {
    flow().skipAuth();
    flow().setGender('Female');
    flow().next();
    flow().setActivity('Heavy');
    flow().toggleDiet('High protein');
    flow().toggleAllergy('Soy');
    flow().scanRx();
    final rows =
        Map.fromEntries(st().summaryRows.map((r) => MapEntry(r.$1, r.$2)));
    expect(rows['Sex'], 'Female');
    expect(rows['Activity'], 'Heavy');
    expect(rows['Preferences'], 'High protein');
    expect(rows['Avoiding'], 'Soy');
    expect(rows['Medications'], 'Telmisartan, Metformin');
    expect(rows['Body'], '72 KG · 174 cm', reason: 'placeholder fallbacks');
  });

  test('restart wipes the machine back to login', () {
    flow().skipAuth();
    flow().setGender('Male');
    flow().toggleDiet('Vegan');
    flow().restart();
    final s = st();
    expect(s.oScreen, OnbScreen.login);
    expect(s.oStep, 0);
    expect(s.oGender, isNull);
    expect(s.oDiet, isEmpty);
  });

  testWidgets('submitPhone runs the fake OTP autofill', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final cc = ProviderContainer();
    addTearDown(cc.dispose);
    final f = cc.read(onboardingFlowProvider.notifier);
    OnboardingState s() => cc.read(onboardingFlowProvider);

    f.submitPhone();
    expect(s().oScreen, OnbScreen.otp);
    expect(s().oOtp, '');

    await tester.pump(const Duration(milliseconds: 950));
    expect(s().oOtp, '4');

    await tester.pump(const Duration(milliseconds: 1000)); // ~1950ms elapsed
    expect(s().oOtp, '4192');
    expect(s().otpComplete, isTrue);

    f.verifyOtp();
    expect(s().oScreen, OnbScreen.steps);
    expect(s().oStep, 0);
  });

  testWidgets('last step -> build() progresses to done via timers',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final cc = ProviderContainer();
    addTearDown(cc.dispose);
    final f = cc.read(onboardingFlowProvider.notifier);
    OnboardingState s() => cc.read(onboardingFlowProvider);

    f.skipAuth();
    for (var i = 0; i < 5; i++) {
      f.next();
    }
    expect(s().oStep, 5);
    f.next(); // step 5 -> startBuilding()
    expect(s().oScreen, OnbScreen.building);
    expect(s().oBuild, 0);

    await tester.pump(const Duration(milliseconds: 800));
    expect(s().oBuild, 1);
    await tester.pump(const Duration(milliseconds: 1200)); // ~2000ms
    expect(s().oBuild, 3);
    await tester.pump(const Duration(milliseconds: 700)); // ~2700ms
    expect(s().oScreen, OnbScreen.done);

    // reaching done does NOT itself flip the router gate - that is the
    // widget's job (OnboardingScreen.onComplete).
    expect(cc.read(onboardingCompleteProvider), isFalse);
  });

  test('is fully independent of the main-app machine', () {
    flow().skipAuth();
    flow().setActivity('Moderate');
    expect(c.read(mainAppProvider).screen, MainScreen.home,
        reason: 'main-app machine untouched by onboarding');

    c.read(mainAppProvider.notifier).goTab(MainScreen.meds);
    expect(st().oScreen, OnbScreen.steps, reason: 'onboarding state not disturbed');
    expect(st().oActivity, 'Moderate');
    expect(c.read(onboardingCompleteProvider), isFalse);
  });
}
