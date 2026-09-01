import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_api.dart';
import '../core/auth_repository.dart';
import '../core/fit_api.dart';
import '../core/lifestyle_api.dart';
import '../core/me_api.dart';
import '../core/pin_lock.dart';
import '../core/vault_api.dart';

/// SECOND, independent state machine — the sign-in + 6-step profile wizard
/// (turn `2a` in CareCart App.dc.html). Every key is `o`-prefixed and lives in
/// its own provider so it can never collide with the main-app machine
/// ([mainAppProvider]) from 2.3. See CLAUDE.md: keep the two fully separate.
///
/// `onboardingCompleteProvider` (the router gate) is a different thing again —
/// this machine flips it once, on reaching `done`, to hand off to the app.
///
/// Phase 6.1: this now talks to the real backend — `POST /auth/request-otp`,
/// `POST /auth/verify-otp`, then `PUT /me/health-profile` + `POST /me/allergies`
/// + `POST /me/medications` during the "building" step. The staged timers that
/// used to fake all of this are gone; the only cosmetic delay left is a short
/// beat on the `done` screen (handled in the widget).

enum OnbScreen { login, otp, steps, building, done }

enum OnbStep { gender, activity, body, diet, allergies, meds, lifestyle, pin }

const kOnbSteps = [
  OnbStep.gender,
  OnbStep.activity,
  OnbStep.body,
  OnbStep.diet,
  OnbStep.allergies,
  OnbStep.meds,
  OnbStep.lifestyle,
  OnbStep.pin,
];

/// Digits in the SMS code (`settings.otp_length` on the backend).
const kOtpLength = 6;

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
    this.oName = '',
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
    this.oExerciseDays,
    this.oSleep,
    this.oSmoking,
    this.oAlcohol,
    this.oStress,
    this.oPin = '',
    this.oPinConfirm = '',
    this.oBuild = 0,
    this.oBusy = false,
    this.oError,
    this.oDevCode,
  });

  final OnbScreen oScreen;
  final int oStep; // 0..5
  final String oName; // what the user wants to be called (PATCH /me)
  final String oPhone;
  final String oOtp; // up to kOtpLength digits
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

  // ---- lifestyle (CareCart Fit inputs) ----
  final int? oExerciseDays; // 0..7 — also derives oActivity for ceilings
  final double? oSleep; // hours/night
  final String? oSmoking; // none | occasional | daily
  final String? oAlcohol; // none | occasional | weekly | daily
  final int? oStress; // 1..5

  // ---- medications PIN (set once here, guards later add/delete) ----
  final String oPin;
  final String oPinConfirm;
  bool get oPinValid => RegExp(r'^\d{4,6}$').hasMatch(oPin);
  bool get oPinReady => oPinValid && oPin == oPinConfirm;

  final int oBuild; // 0..4 build-step progress

  /// A network call is in flight (disables the primary button).
  final bool oBusy;

  /// Last error to show inline (login / OTP / building). Cleared on the next
  /// action.
  final String? oError;

  /// The SMS code echoed by a dev / test backend so local + CI runs work with
  /// no SMS provider. Null against a production backend — the user types it.
  final String? oDevCode;

  OnbStep get oStepKind => kOnbSteps[oStep];
  int get oStepNo => oStep + 1;
  double get oBarFraction => (oStep + 1) / kOnbSteps.length;
  bool get otpComplete => oOtp.length == kOtpLength;
  String get oPhoneShown => oPhone.isEmpty ? '98765 43210' : oPhone;

  /// Just the digits the user typed (any spaces / dashes stripped).
  String get oPhoneDigits => oPhone.replaceAll(RegExp(r'\D'), '');

  /// A 10-digit Indian mobile number starting 6–9 (client-side gate; the server
  /// re-validates via `normalize_e164`).
  bool get oPhoneValid => RegExp(r'^[6-9]\d{9}$').hasMatch(oPhoneDigits);

  /// Phone in E.164 for the API (UI shows a +91 prefix and a national number).
  String get oPhoneE164 {
    final d = oPhoneDigits;
    if (d.isEmpty) return '';
    return d.startsWith('91') && d.length > 10 ? '+$d' : '+91$d';
  }

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
      ('Lifestyle', _lifestyleSummary),
    ];
  }

  String get _lifestyleSummary {
    final bits = <String>[
      if (oSleep != null) '${oSleep!.toStringAsFixed(1)} h sleep',
      if (oExerciseDays != null) '$oExerciseDays d/wk active',
      if (oSmoking != null && oSmoking != 'none') 'smokes $oSmoking',
      if (oAlcohol != null && oAlcohol != 'none') 'alcohol $oAlcohol',
      if (oStress != null) 'stress $oStress/5',
    ];
    return bits.isEmpty ? 'Not given' : bits.join(' · ');
  }

  OnboardingState copyWith({
    OnbScreen? oScreen,
    int? oStep,
    String? oName,
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
    Object? oExerciseDays = _sentinel,
    Object? oSleep = _sentinel,
    Object? oSmoking = _sentinel,
    Object? oAlcohol = _sentinel,
    Object? oStress = _sentinel,
    String? oPin,
    String? oPinConfirm,
    int? oBuild,
    bool? oBusy,
    Object? oError = _sentinel,
    Object? oDevCode = _sentinel,
  }) {
    return OnboardingState(
      oScreen: oScreen ?? this.oScreen,
      oStep: oStep ?? this.oStep,
      oName: oName ?? this.oName,
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
      oExerciseDays: identical(oExerciseDays, _sentinel)
          ? this.oExerciseDays
          : oExerciseDays as int?,
      oSleep: identical(oSleep, _sentinel) ? this.oSleep : oSleep as double?,
      oSmoking:
          identical(oSmoking, _sentinel) ? this.oSmoking : oSmoking as String?,
      oAlcohol:
          identical(oAlcohol, _sentinel) ? this.oAlcohol : oAlcohol as String?,
      oStress: identical(oStress, _sentinel) ? this.oStress : oStress as int?,
      oPin: oPin ?? this.oPin,
      oPinConfirm: oPinConfirm ?? this.oPinConfirm,
      oBuild: oBuild ?? this.oBuild,
      oBusy: oBusy ?? this.oBusy,
      oError: identical(oError, _sentinel) ? this.oError : oError as String?,
      oDevCode:
          identical(oDevCode, _sentinel) ? this.oDevCode : oDevCode as String?,
    );
  }

  static const _sentinel = Object();
}

/// The wizard controller. Sign-in and profile writes are real HTTP calls now;
/// step navigation and selection are still local.
class OnboardingFlow extends Notifier<OnboardingState> {
  final List<Timer> _timers = [];

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

  // ---- login ----

  /// "What should we call you?" — drop control characters, keep the leading
  /// edge trimmed while the user is still typing, and cap at the server's
  /// 60-char `display_name` limit.
  void setName(String v) {
    final buf = StringBuffer();
    for (final rune in v.runes) {
      if (rune >= 0x20 && rune != 0x7f) buf.writeCharCode(rune);
    }
    var cleaned = buf.toString().trimLeft();
    if (cleaned.length > 60) cleaned = cleaned.substring(0, 60);
    state = state.copyWith(oName: cleaned);
  }

  void setPhone(String v) => state = state.copyWith(oPhone: v);

  /// `POST /auth/request-otp` → move to the OTP screen. A dev / test backend
  /// echoes the code, which we stage into the boxes so local + CI runs don't
  /// need an SMS. Against production the user types it.
  Future<void> submitPhone() async {
    if (state.oBusy) return;
    if (!state.oPhoneValid) {
      state = state.copyWith(
          oError: 'Enter a 10-digit mobile number (starting 6–9).');
      return;
    }
    state = state.copyWith(oBusy: true, oError: null);
    final res = await ref.read(authApiProvider).requestOtp(state.oPhoneE164);
    _cancelTimers();
    switch (res) {
      case OtpRequested(:final devCode):
        state = state.copyWith(
          oScreen: OnbScreen.otp,
          oOtp: '',
          oBusy: false,
          oError: null,
          oDevCode: devCode,
        );
        if (devCode != null && devCode.length == kOtpLength) {
          // stage the real code in one digit at a time — same feel as before,
          // but it's the code the backend will actually accept.
          for (var i = 1; i <= devCode.length; i++) {
            _timers.add(Timer(Duration(milliseconds: 500 + i * 120), () {
              if (state.oScreen == OnbScreen.otp) {
                state = state.copyWith(oOtp: devCode.substring(0, i));
              }
            }));
          }
        }
      case OtpRequestFailed(:final message):
        state = state.copyWith(oBusy: false, oError: message);
    }
  }

  /// No real social auth yet — nudge the user to the phone flow.
  void skipAuth() => state = state.copyWith(
      oError: 'Social sign-in is coming soon — sign in with your phone number.');

  // ---- otp ----
  void setOtp(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    state = state.copyWith(
      oOtp: digits.length > kOtpLength ? digits.substring(0, kOtpLength) : digits,
      oError: null,
    );
  }

  /// `POST /auth/verify-otp` → store the token pair → profile steps.
  Future<void> verifyOtp() async {
    if (state.oBusy || !state.otpComplete) return;
    _cancelTimers(); // stop the dev-code stagger — we have the full code now
    state = state.copyWith(oBusy: true, oError: null);
    final res =
        await ref.read(authApiProvider).verifyOtp(state.oPhoneE164, state.oOtp);
    switch (res) {
      case OtpVerified(:final session):
        await ref.read(authControllerProvider).signIn(session);
        state = state.copyWith(
            oScreen: OnbScreen.steps, oStep: 0, oBusy: false, oError: null);
      case OtpVerifyFailed(:final message):
        state = state.copyWith(oBusy: false, oOtp: '', oError: message);
    }
  }

  void resendOtp() => submitPhone();

  // ---- steps ----
  void back() {
    switch (state.oScreen) {
      case OnbScreen.otp:
        _cancelTimers();
        state = state.copyWith(oScreen: OnbScreen.login, oOtp: '', oError: null);
      case OnbScreen.steps when state.oStep == 0:
        state = state.copyWith(oScreen: OnbScreen.login);
      case OnbScreen.steps:
        state = state.copyWith(oStep: state.oStep - 1);
      case OnbScreen.login:
      case OnbScreen.building:
      case OnbScreen.done:
        break;
    }
  }

  /// last step -> build(), else next step.
  Future<void> next() async {
    if (state.oScreen != OnbScreen.steps) return;
    if (state.oStep == kOnbSteps.length - 1) {
      await startBuilding();
    } else {
      state = state.copyWith(oStep: state.oStep + 1);
    }
  }

  Future<void> skipRemainingSteps() => startBuilding();

  void setGender(String g) => state = state.copyWith(oGender: g);
  void setActivity(String a) => state = state.copyWith(oActivity: a);

  /// The activity step now asks days/week of activity; we keep the coarse
  /// `oActivity` too because the verdict engine derives nutrient ceilings from
  /// it (0–1 → sedentary, 2–4 → moderate, 5–7 → heavy).
  void setExerciseDays(int n) {
    final d = n.clamp(0, 7);
    final level = d <= 1 ? 'Sedentary' : (d <= 4 ? 'Moderate' : 'Heavy');
    state = state.copyWith(oExerciseDays: d, oActivity: level);
  }

  void setSleep(double h) =>
      state = state.copyWith(oSleep: double.parse(h.clamp(3, 12).toStringAsFixed(1)));
  void setSmoking(String v) => state = state.copyWith(oSmoking: v);
  void setAlcohol(String v) => state = state.copyWith(oAlcohol: v);
  void setStress(int v) => state = state.copyWith(oStress: v.clamp(1, 5));

  void setPin(String v) =>
      state = state.copyWith(oPin: v.replaceAll(RegExp(r'\D'), ''));
  void setPinConfirm(String v) =>
      state = state.copyWith(oPinConfirm: v.replaceAll(RegExp(r'\D'), ''));

  void setUnitW(String u) => state = state.copyWith(oUnitW: u);
  void setUnitH(String u) => state = state.copyWith(oUnitH: u);
  void setWeight(String v) => state = state.copyWith(oWeight: v);
  void setHeight(String v) => state = state.copyWith(oHeight: v);

  /// "Something else you must avoid" — trim, strip control chars, cap at the
  /// server's 120-char limit so a bad paste never reaches the vault.
  void setOther(String v) {
    final cleaned = v
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .trimLeft();
    state = state.copyWith(
        oOther: cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned);
  }

  void toggleDiet(String v) => state = state.copyWith(oDiet: _toggle(state.oDiet, v));
  void toggleAllergy(String v) =>
      state = state.copyWith(oAllergy: _toggle(state.oAllergy, v));

  static List<String> _toggle(List<String> list, String v) =>
      list.contains(v) ? [for (final x in list) if (x != v) x] : [...list, v];

  /// Add a medication the user picked from the `/drugs/search` catalogue.
  /// Dosage is left blank here — they can set it later on the meds screen.
  void addRxNamed(String name) {
    final n = name.trim();
    if (n.isEmpty || state.oRx.any((r) => r.name.toLowerCase() == n.toLowerCase())) {
      return;
    }
    state = state.copyWith(oRx: [...state.oRx, RxEntry(n, '', '')]);
  }

  void removeRx(int i) =>
      state = state.copyWith(oRx: [for (var j = 0; j < state.oRx.length; j++) if (j != i) state.oRx[j]]);

  // ---- building: the real profile writes ----
  /// Parse a body-metric field, but only pass it on if it's a sane number —
  /// otherwise send null so the vault never stores "999999" or "abc". The
  /// server also range-checks (BodyMetrics ge/le), this is the first gate.
  double? _num(String s, {required double min, required double max}) {
    final n = double.tryParse(s.trim());
    if (n == null || n < min || n > max) return null;
    return n;
  }

  /// Write the profile to the vault, one visible step at a time, then -> done.
  /// A failure surfaces on this screen with a Retry; nothing half-written blocks
  /// the user (the app also lets them edit everything later).
  Future<void> startBuilding() async {
    state = state.copyWith(oScreen: OnbScreen.building, oBuild: 0, oError: null);
    final vault = ref.read(vaultApiProvider);

    // The name they gave on the first step → PATCH /me. Best-effort: a failure
    // here just means the app greets them generically, so don't block the
    // profile write or surface a retry for it.
    if (state.oName.trim().isNotEmpty) {
      await ref.read(meApiProvider).updateName(state.oName);
      ref.invalidate(meProvider);
    }

    VaultWrite step = await vault.putHealthProfile(
      gender: state.oGender?.toLowerCase(),
      activityLevel: state.oActivity?.toLowerCase(),
      // kg 20–350 / lb 44–770 ; cm 90–250 / inch 36–100
      weight: _num(state.oWeight,
          min: 20, max: state.oUnitW.toUpperCase() == 'LB' ? 770 : 350),
      height: _num(state.oHeight,
          min: state.oUnitH.toLowerCase() == 'inch' ? 36 : 90,
          max: state.oUnitH.toLowerCase() == 'inch' ? 100 : 250),
      weightUnit: state.oUnitW.toLowerCase(),
      heightUnit: state.oUnitH,
      diet: state.oDiet,
    );
    if (step case VaultError(:final message)) {
      state = state.copyWith(oError: message);
      return;
    }
    state = state.copyWith(oBuild: 1);

    final allergens = [...state.oAllergy, if (state.oOther.trim().isNotEmpty) state.oOther.trim()];
    for (final a in allergens) {
      step = await vault.addAllergy(a);
      if (step case VaultError(:final message)) {
        state = state.copyWith(oError: message);
        return;
      }
    }
    state = state.copyWith(oBuild: 2);

    for (final rx in state.oRx) {
      step = await vault.addMedication(rx.name, dosage: rx.dose);
      if (step case VaultError(:final message)) {
        state = state.copyWith(oError: message);
        return;
      }
    }
    state = state.copyWith(oBuild: 3);

    // Lifestyle answers → PUT /me/lifestyle-profile. Best-effort: a failure just
    // means the Fit score starts without them; the user can add them later from
    // the profile page. Don't block the hand-off or surface a retry.
    final life = LifestyleProfile(
      sleepHours: state.oSleep,
      exerciseDays: state.oExerciseDays,
      smoking: state.oSmoking,
      alcohol: state.oAlcohol,
      stress: state.oStress,
    );
    if (!life.isEmpty) {
      await ref.read(lifestyleApiProvider).put(life);
      ref.invalidate(lifestyleProfileProvider);
      ref.invalidate(fitProvider);
    }

    // The medications PIN, set on the last step. On-device only (salted hash in
    // secure storage) — nothing about it goes to the server.
    if (state.oPinReady) {
      await ref.read(pinLockProvider).setPin(state.oPin);
    }

    // (nothing more to persist; step 4 is "encrypting on device" flavour)
    state = state.copyWith(oBuild: 4, oScreen: OnbScreen.done);
  }

  /// Retry from the "building" screen after a failed write.
  Future<void> retryBuilding() async {
    if (state.oScreen == OnbScreen.building) await startBuilding();
  }

  // ---- done ----
  /// Sign out locally and start over (used by "run the walkthrough again").
  Future<void> restart() async {
    _cancelTimers();
    await ref.read(authControllerProvider).signOut();
    state = const OnboardingState();
  }
}

final onboardingFlowProvider =
    NotifierProvider<OnboardingFlow, OnboardingState>(OnboardingFlow.new);
