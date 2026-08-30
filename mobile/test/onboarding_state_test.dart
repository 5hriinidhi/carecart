// The onboarding state machine (the `o*`-prefixed keys, turn 2a of the
// prototype). Phase 6.1: sign-in and the profile writes are real backend calls
// now, driven here against in-memory fakes. Covers login -> otp -> 6 steps ->
// building (real vault writes) -> done, and that it never touches the main-app
// machine or the router gate.

import 'package:carecart/src/core/api_client.dart';
import 'package:carecart/src/routing/app_router.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:carecart/src/state/onboarding_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

void main() {
  late ProviderContainer c;
  late FakeAuthApi auth;
  late FakeVaultApi vault;
  late FakeMeApi me;

  OnboardingFlow flow() => c.read(onboardingFlowProvider.notifier);
  OnboardingState st() => c.read(onboardingFlowProvider);

  setUp(() {
    auth = FakeAuthApi(devCode: '123456');
    vault = FakeVaultApi();
    me = FakeMeApi(displayName: null);
    c = ProviderContainer(
        overrides: fakeBackendOverrides(auth: auth, vault: vault, me: me));
  });
  tearDown(() => c.dispose());

  /// login -> otp screen -> code filled -> steps
  Future<void> signIn() async {
    flow().setPhone('9876543210');
    await flow().submitPhone();
    expect(st().oScreen, OnbScreen.otp);
    flow().setOtp('123456');
    await flow().verifyOtp();
    expect(st().oScreen, OnbScreen.steps);
  }

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

  test('submitPhone calls request-otp and moves to the OTP screen', () async {
    flow().setPhone('98765 43210');
    await flow().submitPhone();
    expect(auth.requestedPhones.single, '+919876543210');
    expect(st().oScreen, OnbScreen.otp);
    expect(st().oDevCode, '123456');
  });

  test('submitPhone rejects a too-short number without calling the API', () async {
    flow().setPhone('123');
    await flow().submitPhone();
    expect(auth.requestedPhones, isEmpty);
    expect(st().oScreen, OnbScreen.login);
    expect(st().oError, isNotNull);
  });

  test('phone validation (client-side): 10 digits, starts 6-9', () async {
    for (final bad in ['12345', '1234567890', '5876543210', '98765432101']) {
      flow().setPhone(bad);
      expect(st().oPhoneValid, isFalse, reason: bad);
      await flow().submitPhone();
      expect(st().oScreen, OnbScreen.login, reason: bad);
    }
    expect(auth.requestedPhones, isEmpty);

    flow().setPhone('9876543210');
    expect(st().oPhoneValid, isTrue);
    await flow().submitPhone();
    expect(auth.requestedPhones.single, '+919876543210');
  });

  test('setOther trims, strips control chars and caps at 120', () {
    flow().setOther('  mustard\x00 \x07seed  ');
    expect(st().oOther, 'mustard seed  '.trimLeft());
    flow().setOther('x' * 200);
    expect(st().oOther.length, 120);
  });

  test('setName strips control chars, left-trims and caps at 60', () {
    expect(st().oName, '');
    flow().setName('  Ka\x00ir\x1f a  ');
    expect(st().oName, 'Kair a  '); // controls gone, leading ws trimmed
    flow().setName('n' * 90);
    expect(st().oName.length, 60);
  });

  test('a request-otp failure surfaces on the login screen', () async {
    auth.requestFails = 'Too many code requests.';
    flow().setPhone('9876543210');
    await flow().submitPhone();
    expect(st().oScreen, OnbScreen.login);
    expect(st().oError, 'Too many code requests.');
    expect(st().oBusy, isFalse);
  });

  test('verifyOtp is a no-op until all 6 digits are present', () async {
    flow().setPhone('9876543210');
    await flow().submitPhone();
    flow().setOtp('123');
    expect(st().otpComplete, isFalse);
    await flow().verifyOtp();
    expect(st().oScreen, OnbScreen.otp, reason: 'still waiting for the code');
  });

  test('verifyOtp stores the token and advances to the steps', () async {
    await signIn();
    expect(auth.verifiedWith.single.code, '123456');
    expect(c.read(authTokenProvider), 'fake.access.+919876543210');
    expect(st().oStep, 0);
    expect(st().oStepKind, OnbStep.gender);
  });

  test('a wrong code clears the field and shows an error', () async {
    auth.verifyFails = 'That code is wrong or has expired.';
    flow().setPhone('9876543210');
    await flow().submitPhone();
    flow().setOtp('000000');
    await flow().verifyOtp();
    expect(st().oScreen, OnbScreen.otp);
    expect(st().oOtp, '');
    expect(st().oError, 'That code is wrong or has expired.');
  });

  test('next walks the 6 steps in order, then enters building', () async {
    await signIn();
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

  test('back: first step and the OTP screen both return to login', () async {
    await signIn();
    flow().next();
    expect(st().oStep, 1);
    flow().back();
    expect(st().oStep, 0);
    flow().back();
    expect(st().oScreen, OnbScreen.login);

    flow().setPhone('9876543210');
    await flow().submitPhone();
    expect(st().oScreen, OnbScreen.otp);
    flow().back();
    expect(st().oScreen, OnbScreen.login);
    expect(st().oOtp, '');
  });

  test('gender and activity are single-select', () async {
    await signIn();
    flow().setGender('Male');
    flow().setGender('Female');
    expect(st().oGender, 'Female');
    flow().next();
    flow().setActivity('Moderate');
    expect(st().oActivity, 'Moderate');
  });

  test('diet / allergy toggle in and out; body fields update', () async {
    await signIn();
    flow().toggleDiet('Low sodium');
    flow().toggleDiet('Vegan');
    flow().toggleDiet('Low sodium');
    expect(st().oDiet, const ['Vegan']);
    flow().toggleAllergy('Peanuts');
    expect(st().oAllergy, const ['Peanuts']);
    flow().setOther('mustard');
    flow().setUnitW('Lb');
    flow().setWeight('70');
    flow().setHeight('180');
    final s = st();
    expect(s.oUnitW, 'Lb');
    expect(s.oWeight, '70');
    expect(s.oHeight, '180');
    expect(s.oOther, 'mustard');
  });

  test('scanRx / addRx / removeRx manage the prescription list', () {
    flow().scanRx();
    expect(flow().state.oRx.map((r) => r.name), const ['Telmisartan', 'Metformin']);
    flow().addRx();
    expect(flow().state.oRx.map((r) => r.name),
        const ['Telmisartan', 'Metformin', 'Atorvastatin']);
    flow().removeRx(1);
    expect(flow().state.oRx.map((r) => r.name), const ['Telmisartan', 'Atorvastatin']);
  });

  test('startBuilding writes the whole profile to the vault, then -> done',
      () async {
    await signIn();
    flow().setName('Kiran');
    flow().setGender('Female');
    flow().next();
    flow().setActivity('Moderate');
    flow().next();
    flow().setWeight('61');
    flow().setHeight('164');
    flow().next();
    flow().toggleDiet('Low sodium');
    flow().next();
    flow().toggleAllergy('Tree nuts');
    flow().setOther('mustard');
    flow().next();
    flow().scanRx(); // Telmisartan + Metformin
    await flow().next(); // last step -> startBuilding()

    expect(st().oScreen, OnbScreen.done);
    expect(me.nameWrites, const ['Kiran']); // PATCH /me happened during building
    expect(vault.profile!['gender'], 'female');
    expect(vault.profile!['activity_level'], 'moderate');
    expect(vault.profile!['diet'], const ['Low sodium']);
    expect(vault.allergies, const ['Tree nuts', 'mustard']);
    expect(vault.medications.map((m) => m.name), const ['Telmisartan', 'Metformin']);

    // reaching done does NOT itself flip the router gate — that's the widget's job
    expect(c.read(onboardingCompleteProvider), isFalse);
  });

  test('a failed vault write stops on the building screen with an error',
      () async {
    vault.failOn = {'health-profile'};
    await signIn();
    for (var i = 0; i < 5; i++) {
      flow().next();
    }
    await flow().next(); // -> startBuilding, which fails on the first write
    expect(st().oScreen, OnbScreen.building);
    expect(st().oError, contains('health-profile'));

    // retry succeeds once the failure is cleared
    vault.failOn = const {};
    await flow().retryBuilding();
    expect(st().oScreen, OnbScreen.done);
  });

  test('restart signs out and wipes the machine back to login', () async {
    await signIn();
    flow().setGender('Male');
    flow().toggleDiet('Vegan');
    await flow().restart();
    final s = st();
    expect(s.oScreen, OnbScreen.login);
    expect(s.oGender, isNull);
    expect(s.oDiet, isEmpty);
    expect(c.read(authTokenProvider), isNull);
  });

  test('is fully independent of the main-app machine', () async {
    await signIn();
    flow().setActivity('Moderate');
    expect(c.read(mainAppProvider).screen, MainScreen.home);

    c.read(mainAppProvider.notifier).goTab(MainScreen.meds);
    expect(st().oScreen, OnbScreen.steps);
    expect(st().oActivity, 'Moderate');
    expect(c.read(onboardingCompleteProvider), isFalse);
  });

  testWidgets('a dev-code backend stages the real code into the boxes',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final cc = ProviderContainer(
        overrides: fakeBackendOverrides(auth: FakeAuthApi(devCode: '246810')));
    addTearDown(cc.dispose);
    final f = cc.read(onboardingFlowProvider.notifier);
    OnboardingState s() => cc.read(onboardingFlowProvider);

    f.setPhone('9876543210');
    await f.submitPhone();
    expect(s().oScreen, OnbScreen.otp);
    expect(s().oOtp, '');

    await tester.pump(const Duration(milliseconds: 700));
    expect(s().oOtp.isNotEmpty, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(s().oOtp, '246810');
    expect(s().otpComplete, isTrue);
  });
}
