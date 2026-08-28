import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// SECOND, independent state machine — the sign-in + 6-step profile wizard
/// (turn `2a` in CareCart App.dc.html). Every key is `o`-prefixed and lives in
/// its own provider so it can never collide with the main-app machine
/// ([mainAppProvider]) from 2.3. See CLAUDE.md: keep the two fully separate.
///
/// `onboardingCompleteProvider` (the router gate) is a different thing again —
/// this machine flips it once, on reaching `done`, to hand off to the app.

enum OnbScreen { login, otp, steps, building, done }

enum OnbStep { gender, activity, body, diet, allergies, meds }

const kOnbSteps = [
  OnbStep.gender,
  OnbStep.activity,
  OnbStep.body,
  OnbStep.diet,
  OnbStep.allergies,
  OnbStep.meds,
];

@immutable
class RxEntry {
  const RxEntry(this.name, this.dose, this.schedule);
  final String name;
  final String dose;
  final String schedule;
}

@immutable
class OnboardingState {
  const OnboardingState({
    this.oScreen = OnbScreen.login,
    this.oStep = 0,
    this.oPhone = '',
    this.oOtp = '',
    this.oGender,
    this.oActivity,
    this.oUnitW = 'KG',
    this.oUnitH = 'cm',
    this.oWeight = '',
    this.oHeight = '',
    this.oDiet = const [],
    this.oAllergy = const [],
    this.oOther = '',
    this.oRx = const [],
    this.oBuild = 0,
  });

  final OnbScreen oScreen;
  final int oStep; // 0..5
  final String oPhone;
  final String oOtp; // 0..4 digits, auto-filled by fake OTP
  final String? oGender; // Male | Female | Prefer not to say
  final String? oActivity; // Sedentary | Moderate | Heavy
  final String oUnitW; // KG | Lb
  final String oUnitH; // cm | inch
  final String oWeight;
  final String oHeight;
  final List<String> oDiet;
  final List<String> oAllergy;
  final String oOther;
  final List<RxEntry> oRx;
  final int oBuild; // 0..4 build-step progress

  OnbStep get oStepKind => kOnbSteps[oStep];
  int get oStepNo => oStep + 1;
  double get oBarFraction => (oStep + 1) / kOnbSteps.length;
  bool get otpComplete => oOtp.length == 4;
  String get oPhoneShown => oPhone.isEmpty ? '98765 43210' : oPhone;

  /// The rows shown on the `done` screen (prototype `summaryRows`).
  List<(String, String)> get summaryRows {
    final avoiding = [...oAllergy, if (oOther.isNotEmpty) oOther];
    return [
      ('Sex', oGender ?? 'Not given'),
      ('Activity', oActivity ?? 'Not given'),
      ('Body', '${oWeight.isEmpty ? "72" : oWeight} $oUnitW · '
          '${oHeight.isEmpty ? "174" : oHeight} $oUnitH'),
      ('Preferences', oDiet.isEmpty ? 'None set' : oDiet.join(', ')),
      ('Avoiding', avoiding.isEmpty ? 'Nothing flagged' : avoiding.join(', ')),
      ('Medications',
          oRx.isEmpty ? 'None added' : oRx.map((r) => r.name).join(', ')),
    ];
  }

  OnboardingState copyWith({
    OnbScreen? oScreen,
    int? oStep,
    String? oPhone,
    String? oOtp,
    Object? oGender = _sentinel,
    Object? oActivity = _sentinel,
    String? oUnitW,
    String? oUnitH,
    String? oWeight,
    String? oHeight,
    List<String>? oDiet,
    List<String>? oAllergy,
    String? oOther,
    List<RxEntry>? oRx,
    int? oBuild,
  }) {
    return OnboardingState(
      oScreen: oScreen ?? this.oScreen,
      oStep: oStep ?? this.oStep,
      oPhone: oPhone ?? this.oPhone,
      oOtp: oOtp ?? this.oOtp,
      oGender: identical(oGender, _sentinel) ? this.oGender : oGender as String?,
      oActivity:
          identical(oActivity, _sentinel) ? this.oActivity : oActivity as String?,
      oUnitW: oUnitW ?? this.oUnitW,
      oUnitH: oUnitH ?? this.oUnitH,
      oWeight: oWeight ?? this.oWeight,
      oHeight: oHeight ?? this.oHeight,
      oDiet: oDiet ?? this.oDiet,
      oAllergy: oAllergy ?? this.oAllergy,
      oOther: oOther ?? this.oOther,
      oRx: oRx ?? this.oRx,
      oBuild: oBuild ?? this.oBuild,
    );
  }

  static const _sentinel = Object();
}

/// The wizard controller. Methods mirror the prototype handlers
/// (`goOtp`, `oOtpNext`, `oSkipAuth`, `oBack`, `oNext`, `build`, `toggleIn`,
/// `oScanRx`, `oAddRx`, `oRestart`). OTP verification and the "building"
/// progression are faked with local timers, exactly like the prototype's
/// `setTimeout` chain - there is no backend yet.
class OnboardingFlow extends Notifier<OnboardingState> {
  final List<Timer> _timers = [];
  int _gen = 0; // bumped on every phase change; stale timer callbacks bail

  @override
  OnboardingState build() {
    ref.onDispose(_cancelTimers);
    return const OnboardingState();
  }

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void _phase(void Function() apply) {
    _cancelTimers();
    _gen++;
    apply();
  }

  /// schedule [fn] after [ms]; it only runs if no newer phase started meanwhile.
  void _later(int ms, void Function() fn) {
    final gen = _gen;
    _timers.add(Timer(Duration(milliseconds: ms), () {
      if (gen == _gen) fn();
    }));
  }

  // ---- login ----
  void setPhone(String v) => state = state.copyWith(oPhone: v);

  /// prototype `goOtp` - move to the OTP screen and fake the code arriving.
  void submitPhone() {
    _phase(() => state = state.copyWith(oScreen: OnbScreen.otp, oOtp: ''));
    const fills = ['4', '41', '419', '4192'];
    for (var i = 0; i < fills.length; i++) {
      _later(900 + i * 260, () => state = state.copyWith(oOtp: fills[i]));
    }
  }

  /// prototype `oSkipAuth` on the login screen - straight to the profile steps.
  void skipAuth() =>
      _phase(() => state = state.copyWith(oScreen: OnbScreen.steps, oStep: 0));

  // ---- otp ----
  /// prototype `oOtpNext` - only advances once the 4 digits have "arrived".
  void verifyOtp() {
    if (!state.otpComplete) return;
    _phase(() => state = state.copyWith(oScreen: OnbScreen.steps, oStep: 0));
  }

  void resendOtp() => submitPhone();

  // ---- steps ----
  /// prototype `oBack`: from OTP or the first step -> back to login,
  /// otherwise step back one.
  void back() {
    switch (state.oScreen) {
      case OnbScreen.otp:
        _phase(() => state = state.copyWith(oScreen: OnbScreen.login, oOtp: ''));
      case OnbScreen.steps when state.oStep == 0:
        _phase(() => state = state.copyWith(oScreen: OnbScreen.login));
      case OnbScreen.steps:
        state = state.copyWith(oStep: state.oStep - 1);
      case OnbScreen.login:
      case OnbScreen.building:
      case OnbScreen.done:
        break;
    }
  }

  /// prototype `oNext`: last step -> build(), else next step.
  void next() {
    if (state.oScreen != OnbScreen.steps) return;
    if (state.oStep == kOnbSteps.length - 1) {
      startBuilding();
    } else {
      state = state.copyWith(oStep: state.oStep + 1);
    }
  }

  /// "Skip for now" on the steps header - build the profile with what we have.
  /// (The prototype reuses `oSkipAuth` here, which just resets to step 0; that
  /// is a copy-paste artefact, so we do the sensible thing instead.)
  void skipRemainingSteps() => startBuilding();

  void setGender(String g) => state = state.copyWith(oGender: g);
  void setActivity(String a) => state = state.copyWith(oActivity: a);
  void setUnitW(String u) => state = state.copyWith(oUnitW: u);
  void setUnitH(String u) => state = state.copyWith(oUnitH: u);
  void setWeight(String v) => state = state.copyWith(oWeight: v);
  void setHeight(String v) => state = state.copyWith(oHeight: v);
  void setOther(String v) => state = state.copyWith(oOther: v);

  void toggleDiet(String v) => state = state.copyWith(oDiet: _toggle(state.oDiet, v));
  void toggleAllergy(String v) =>
      state = state.copyWith(oAllergy: _toggle(state.oAllergy, v));

  static List<String> _toggle(List<String> list, String v) =>
      list.contains(v) ? [for (final x in list) if (x != v) x] : [...list, v];

  /// prototype `oScanRx` - pretend the scanner read two prescriptions.
  void scanRx() => state = state.copyWith(oRx: const [
        RxEntry('Telmisartan', '40 mg', 'morning'),
        RxEntry('Metformin', '500 mg', 'twice daily'),
      ]);

  /// prototype `oAddRx` - pretend the user typed one in.
  void addRx() => state = state.copyWith(
      oRx: [...state.oRx, const RxEntry('Atorvastatin', '10 mg', 'night')]);

  void removeRx(int i) =>
      state = state.copyWith(oRx: [for (var j = 0; j < state.oRx.length; j++) if (j != i) state.oRx[j]]);

  // ---- building ----
  /// prototype `build()` - fake the profile-build progression, then -> done.
  void startBuilding() {
    _phase(() =>
        state = state.copyWith(oScreen: OnbScreen.building, oBuild: 0));
    _later(700, () => state = state.copyWith(oBuild: 1));
    _later(1350, () => state = state.copyWith(oBuild: 2));
    _later(1950, () => state = state.copyWith(oBuild: 3));
    _later(2600, () => state = state.copyWith(oScreen: OnbScreen.done));
  }

  // ---- done ----
  /// prototype `oRestart` - run the walkthrough again from the top.
  void restart() => _phase(() => state = const OnboardingState());
}

final onboardingFlowProvider =
    NotifierProvider<OnboardingFlow, OnboardingState>(OnboardingFlow.new);
