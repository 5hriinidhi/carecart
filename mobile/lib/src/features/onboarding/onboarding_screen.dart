import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../routing/app_router.dart';
import '../../state/onboarding_state.dart';

/// The sign-in -> OTP -> 6 profile steps -> profile-build -> done flow
/// (turn `2a` in `CareCart App.dc.html`). Driven entirely by
/// [onboardingFlowProvider] - the SECOND state machine, independent of the
/// main-app one. On reaching `done` it flips [onboardingCompleteProvider],
/// which the router redirect turns into a jump to `/app` (the 2.3 home shell).
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key, this.onComplete});

  /// Overridable so the debug gallery can host the flow without touching the
  /// real router gate. Null in the app -> flips [onboardingCompleteProvider].
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = ref.watch(onboardingFlowProvider.select((s) => s.oScreen));
    final complete = onComplete ??
        () => ref.read(onboardingCompleteProvider.notifier).markDone();

    // "On reaching oScreen 'done', navigate into the main app's home screen."
    // Show the summary for a beat, then hand off (the done screen's CTA lets an
    // eager user skip the wait).
    ref.listen<OnbScreen>(
      onboardingFlowProvider.select((s) => s.oScreen),
      (prev, next) {
        if (next == OnbScreen.done && prev != OnbScreen.done) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (context.mounted) complete();
          });
        }
      },
    );

    return switch (screen) {
      OnbScreen.login => const _LoginView(),
      OnbScreen.otp => const _OtpView(),
      OnbScreen.steps => const _StepsView(),
      OnbScreen.building => const _BuildingView(),
      OnbScreen.done => _DoneView(onEnterApp: complete),
    };
  }
}

// ---------------------------------------------------------------------------
// shared tokens + tiny type helpers
// ---------------------------------------------------------------------------

const _dim = Color(0xFFEAEADB);
const _faint = Color(0xFFA3A491);
const _note = Color(0xFF5C5E4D);
const _chipInk = Color(0xFF4A4C3D);
const _peach = Color(0xFFF7E2D5);
const _peachInk = Color(0xFF7A4A31);
const _hair = Color(0x1F15150F);

TextStyle _bric(double size, FontWeight w,
        {Color color = Cc.ink, double height = 1.2}) =>
    TextStyle(
        fontFamily: 'Bricolage',
        fontSize: size,
        fontWeight: w,
        color: color,
        height: height);

TextStyle _sans(double size,
        {FontWeight? w, Color color = Cc.ink, double height = 1.4}) =>
    TextStyle(
        fontFamily: 'DMSans',
        fontSize: size,
        fontWeight: w,
        color: color,
        height: height);

const _stepCopy = <OnbStep, (String, String)>{
  OnbStep.gender: (
    'A few things about you',
    'Sex changes the nutrient ceilings we hold you to — sodium, iron, protein.'
  ),
  OnbStep.activity: (
    'How many days a week are you active?',
    'A day counts if you moved for ~30 minutes. This sets your energy budget '
        'and feeds your CareCart Fit score.'
  ),
  OnbStep.body: (
    'Your measurements',
    'Used only to calculate per-serving limits. Nothing here is shared or '
        'scored socially.'
  ),
  OnbStep.diet: (
    'Any dietary preferences?',
    'We rank safer swaps inside these boundaries instead of ignoring them.'
  ),
  OnbStep.allergies: (
    'Anything you must avoid?',
    'Allergens are treated as a hard stop, not a deduction from a score.'
  ),
  OnbStep.meds: (
    'What are you taking?',
    'This is the part no other food app does. Every label gets cross-checked '
        'against these.'
  ),
  OnbStep.lifestyle: (
    'A little about your lifestyle',
    'These drive the lifestyle half of your CareCart Fit score. Skip anything '
        'you would rather not answer.'
  ),
};

const _smokingOpts = <(String, String)>[
  ('none', 'Non-smoker'),
  ('occasional', 'Occasionally'),
  ('daily', 'Daily'),
];

const _alcoholOpts = <(String, String)>[
  ('none', 'None'),
  ('occasional', 'Occasionally'),
  ('weekly', 'Weekly'),
  ('daily', 'Most days'),
];

const _genderOpts = <(String, String)>[
  ('Male', 'Sodium ceiling 2,000 mg baseline'),
  ('Female', 'Iron and calcium ceilings adjusted'),
  ('Prefer not to say', 'We use population averages instead'),
];

const _dietOpts = [
  'Low sodium', 'Low sugar', 'Low fat', 'Low potassium',
  'Vegetarian', 'Vegan', 'Jain', 'High protein',
];

const _allergyOpts = [
  'Dairy', 'Egg', 'Soy', 'Wheat', 'Peanuts', 'Shellfish', 'Sesame', 'Tree nuts',
];

const _buildSteps = [
  'Calculating your nutrient ceilings',
  'Loading interaction rules for 2 medications',
  'Indexing 8 allergen alias sets',
  'Encrypting your profile on device',
];

// ---------------------------------------------------------------------------
// login
// ---------------------------------------------------------------------------

class _LoginView extends ConsumerWidget {
  const _LoginView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    final busy = ref.watch(onboardingFlowProvider.select((s) => s.oBusy));
    final error = ref.watch(onboardingFlowProvider.select((s) => s.oError));
    return CcScreen(
      background: Cc.paper,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
        child: Column(
          children: [
            const SizedBox(height: 24),
            const _Brand(),
            const SizedBox(height: 44),
            _LoginForm(flow: flow, busy: busy, error: error),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            children: [
              Positioned(
                left: 12,
                top: 34,
                child: Transform.rotate(
                  angle: -0.733,
                  child: Container(
                    width: 72,
                    height: 30,
                    decoration: BoxDecoration(
                        color: Cc.olive,
                        borderRadius: BorderRadius.circular(99)),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 34,
                child: Transform.rotate(
                  angle: -0.733,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 36,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Cc.sage,
                      borderRadius:
                          BorderRadius.horizontal(left: Radius.circular(99)),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 14,
                child: Transform.rotate(
                  angle: 0.785,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                        color: Cc.accent,
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text('CareCart', style: _bric(30, FontWeight.w800, height: 1.1)),
        const SizedBox(height: 9),
        SizedBox(
          width: 250,
          child: Text(
            "Know what's in the pack before it goes in the trolley.",
            textAlign: TextAlign.center,
            style: _sans(13.5, color: Cc.muted, height: 1.55),
          ),
        ),
      ],
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({required this.flow, this.busy = false, this.error});
  final OnboardingFlow flow;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PHONE NUMBER',
            style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.7,
                color: Cc.muted)),
        const SizedBox(height: 11),
        Container(
          decoration: BoxDecoration(
            color: Cc.paperRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _hair),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('+91', style: _sans(14, w: FontWeight.w500, color: Cc.muted)),
              Container(
                width: 1,
                height: 18,
                color: _hair,
                margin: const EdgeInsets.symmetric(horizontal: 10),
              ),
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: flow.setPhone,
                  style: _sans(15),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    hintText: '98765 43210',
                    hintStyle: _sans(15, color: _faint),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!,
              key: const Key('onb-login-error'),
              style: _sans(12, color: Cc.avoid, height: 1.4)),
        ],
        const SizedBox(height: 11),
        _BigButton(
          label: busy ? 'Sending code…' : 'Continue',
          bg: busy ? _dim : Cc.accent,
          fg: busy ? _faint : Cc.inkSoft,
          onTap: busy ? null : flow.submitPhone,
        ),
        const _OrDivider(),
        _SocialButton(
            label: 'Continue with Apple', dark: true, onTap: flow.skipAuth),
        const SizedBox(height: 11),
        _SocialButton(
            label: 'Continue with Google', dark: false, onTap: flow.skipAuth),
        const SizedBox(height: 14),
        Text(
          'Your health data is encrypted on this device. You can delete all of '
          'it, any time, in one tap.',
          textAlign: TextAlign.center,
          style: _sans(11, color: _faint, height: 1.5),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// otp
// ---------------------------------------------------------------------------

class _OtpView extends ConsumerStatefulWidget {
  const _OtpView();

  @override
  ConsumerState<_OtpView> createState() => _OtpViewState();
}

class _OtpViewState extends ConsumerState<_OtpView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    final s = ref.watch(onboardingFlowProvider);

    // keep the field in sync when the dev-code auto-fills the digits
    if (_controller.text != s.oOtp) {
      _controller.value = TextEditingValue(
        text: s.oOtp,
        selection: TextSelection.collapsed(offset: s.oOtp.length),
      );
    }

    return CcScreen(
      background: Cc.paper,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: flow.back,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: _dim, shape: BoxShape.circle),
                child: const Icon(Icons.chevron_left_rounded,
                    size: 22, color: Cc.inkSoft),
              ),
            ),
            const SizedBox(height: 30),
            Text('Enter the code', style: _bric(26, FontWeight.w700, height: 1.18)),
            const SizedBox(height: 9),
            Text(
              s.oDevCode != null
                  ? "Sent to +91 ${s.oPhoneShown}. It'll fill in by itself in a second."
                  : "Sent to +91 ${s.oPhoneShown}. Enter the $kOtpLength-digit code.",
              style: _sans(13.5, color: Cc.muted, height: 1.55),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                for (var i = 0; i < kOtpLength; i++) ...[
                  Expanded(
                    child: _OtpBox(
                      digit: i < s.oOtp.length ? s.oOtp[i] : '',
                      active: i == s.oOtp.length,
                    ),
                  ),
                  if (i < kOtpLength - 1) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('onb-otp-field'),
              controller: _controller,
              keyboardType: TextInputType.number,
              maxLength: kOtpLength,
              onChanged: flow.setOtp,
              onSubmitted: (_) => flow.verifyOtp(),
              style: _sans(15),
              decoration: InputDecoration(
                counterText: '',
                isCollapsed: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                hintText: 'Type the code',
                hintStyle: _sans(14, color: _faint),
                filled: true,
                fillColor: Cc.paperRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _hair),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _hair),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: s.oBusy ? null : flow.resendOtp,
              child: Text('Resend code', style: _sans(12.5, color: Cc.olive)),
            ),
            if (s.oError != null) ...[
              const SizedBox(height: 12),
              Text(s.oError!,
                  key: const Key('onb-otp-error'),
                  style: _sans(12, color: Cc.avoid, height: 1.4)),
            ],
            const SizedBox(height: 28),
            _BigButton(
              label: s.oBusy
                  ? 'Verifying…'
                  : (s.otpComplete ? 'Verified — continue' : 'Waiting for the code'),
              bg: (s.otpComplete && !s.oBusy) ? Cc.accent : _dim,
              fg: (s.otpComplete && !s.oBusy) ? Cc.inkSoft : _faint,
              onTap: (s.otpComplete && !s.oBusy) ? flow.verifyOtp : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({required this.digit, required this.active});
  final String digit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final border = digit.isNotEmpty
        ? Cc.olive
        : active
            ? Cc.accent
            : _hair;
    return Container(
      height: 62,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(width: 1.5, color: border),
      ),
      child: Text(digit, style: _bric(24, FontWeight.w700)),
    );
  }
}

// ---------------------------------------------------------------------------
// steps
// ---------------------------------------------------------------------------

class _StepsView extends ConsumerWidget {
  const _StepsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    final s = ref.watch(onboardingFlowProvider);
    final (title, why) = _stepCopy[s.oStepKind]!;

    return CcScreen(
      background: Cc.paper,
      safeBottom: true,
      child: Column(
        children: [
          // header: step counter + progress bar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text('STEP ${s.oStepNo} OF 6',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'DMMono',
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1.1,
                              color: Cc.muted)),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: flow.skipRemainingSteps,
                      child: Text('Skip for now',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _sans(11.5, w: FontWeight.w500, color: _faint)),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    height: 5,
                    color: const Color(0x1A20241A),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: s.oBarFraction,
                      child: Container(color: Cc.olive),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
              children: [
                Text(title, style: _bric(24, FontWeight.w700)),
                const SizedBox(height: 8),
                Text(why, style: _sans(12.5, color: Cc.muted, height: 1.55)),
                const SizedBox(height: 20),
                ..._stepBody(s, flow),
              ],
            ),
          ),
          // footer: back + next/complete
          Container(
            decoration: const BoxDecoration(
              color: Cc.paper,
              border: Border(top: BorderSide(color: Color(0x1215150F))),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: flow.back,
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: _dim, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.arrow_back_rounded,
                        size: 19, color: Cc.oliveDark),
                  ),
                ),
                GestureDetector(
                  onTap: flow.next,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                    decoration: BoxDecoration(
                        color: Cc.accent,
                        borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(s.oStep == kOnbSteps.length - 1 ? 'Complete' : 'Next',
                            style:
                                _sans(14, w: FontWeight.w500, color: Cc.inkSoft)),
                        const SizedBox(width: 9),
                        const Icon(Icons.arrow_forward_rounded,
                            size: 19, color: Cc.inkSoft),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<Widget> _stepBody(OnboardingState s, OnboardingFlow flow) {
  switch (s.oStepKind) {
    case OnbStep.gender:
      return [
        Text('What should we call you?',
            style: _sans(13, w: FontWeight.w600, color: Cc.ink)),
        const SizedBox(height: 8),
        _PlainInput(hint: 'Your name', onChanged: flow.setName),
        const SizedBox(height: 24),
        for (final (label, note) in _genderOpts)
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: _SelectCard(
              label: label,
              note: note,
              selected: s.oGender == label,
              big: true,
              onTap: () => flow.setGender(label),
            ),
          ),
      ];
    case OnbStep.activity:
      return [
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (var d = 0; d <= 7; d++)
              _ChoiceChip(
                label: d == 0 ? 'None' : '$d ${d == 1 ? "day" : "days"}',
                selected: s.oExerciseDays == d,
                onTap: () => flow.setExerciseDays(d),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const _InfoBox(
          bg: Cc.sageSoft,
          fg: Cc.oliveDark,
          text:
              'Also sets your energy budget, so a "high calorie" warning only '
              'fires when it is actually high for you.',
        ),
      ];
    case OnbStep.body:
      return [
        _UnitRow(
            title: 'Weight',
            units: const ['KG', 'Lb'],
            value: s.oUnitW,
            onPick: flow.setUnitW),
        const SizedBox(height: 10),
        _BigInput(hint: '72', unit: s.oUnitW, onChanged: flow.setWeight),
        const SizedBox(height: 22),
        _UnitRow(
            title: 'Height',
            units: const ['cm', 'inch'],
            value: s.oUnitH,
            onPick: flow.setUnitH),
        const SizedBox(height: 10),
        _BigInput(hint: '174', unit: s.oUnitH, onChanged: flow.setHeight),
        const SizedBox(height: 18),
        const _InfoBox(
          bg: Cc.sageSoft,
          fg: Cc.oliveDark,
          text:
              'These set your per-serving ceilings — sodium, sugar, potassium — '
              'so a warning means something for your body, not an average one.',
        ),
      ];
    case OnbStep.diet:
      return [
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (final d in _dietOpts)
              _ChoiceChip(
                label: d,
                selected: s.oDiet.contains(d),
                onTap: () => flow.toggleDiet(d),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Pick as many as apply, or none. You can change these later without '
          'redoing anything.',
          style: _sans(12, color: _faint, height: 1.5),
        ),
      ];
    case OnbStep.allergies:
      return [
        _grid2([
          for (final a in _allergyOpts)
            _AllergyTile(
              label: a,
              selected: s.oAllergy.contains(a),
              onTap: () => flow.toggleAllergy(a),
            ),
        ]),
        const SizedBox(height: 18),
        Text('SOMETHING ELSE',
            style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.7,
                color: Cc.muted)),
        const SizedBox(height: 9),
        _PlainInput(hint: 'e.g. mustard, sulphites', onChanged: flow.setOther),
        const SizedBox(height: 16),
        const _InfoBox(
          bg: _peach,
          fg: _peachInk,
          text: 'Allergens get the hardest warning we have — a full-screen stop, '
              'not a score.',
        ),
      ];
    case OnbStep.meds:
      return [
        Row(
          children: [
            Expanded(
              child: _MedTile(
                dark: true,
                icon: Icons.document_scanner_outlined,
                title: 'Scan prescription',
                sub: 'Reads names and doses',
                onTap: flow.scanRx,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MedTile(
                dark: false,
                icon: Icons.add_rounded,
                title: 'Type it in',
                sub: 'Search 12,000 names',
                onTap: flow.addRx,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (s.oRx.isEmpty)
          const _DashedEmpty(
            title: 'Nothing added yet',
            sub: "Not on any medication? That's fine — skip ahead.",
          )
        else
          for (var i = 0; i < s.oRx.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _RxCard(rx: s.oRx[i], onRemove: () => flow.removeRx(i)),
            ),
      ];
    case OnbStep.lifestyle:
      return [
        _LifeLabel('Sleep — hours a night'),
        const SizedBox(height: 8),
        _SleepStepper(
            value: s.oSleep ?? 7.0, onChanged: flow.setSleep),
        const SizedBox(height: 20),
        _LifeLabel('Smoking'),
        const SizedBox(height: 8),
        Wrap(spacing: 9, runSpacing: 9, children: [
          for (final (val, label) in _smokingOpts)
            _ChoiceChip(
                label: label,
                selected: s.oSmoking == val,
                onTap: () => flow.setSmoking(val)),
        ]),
        const SizedBox(height: 20),
        _LifeLabel('Alcohol'),
        const SizedBox(height: 8),
        Wrap(spacing: 9, runSpacing: 9, children: [
          for (final (val, label) in _alcoholOpts)
            _ChoiceChip(
                label: label,
                selected: s.oAlcohol == val,
                onTap: () => flow.setAlcohol(val)),
        ]),
        const SizedBox(height: 20),
        _LifeLabel('Typical stress'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 1; i <= 5; i++) ...[
              Expanded(
                child: _ChoiceChip(
                  label: '$i',
                  selected: s.oStress == i,
                  onTap: () => flow.setStress(i),
                ),
              ),
              if (i < 5) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text('1 = very low · 5 = very high',
            style: _sans(11.5, color: _faint)),
      ];
  }
}

class _LifeLabel extends StatelessWidget {
  const _LifeLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(
          fontFamily: 'DMMono',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.7,
          color: Cc.muted));
}

class _SleepStepper extends StatelessWidget {
  const _SleepStepper({required this.value, required this.onChanged});
  final double value;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData ic, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Cc.paperRaised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x1F151510))),
            child: Icon(ic, size: 20, color: Cc.ink),
          ),
        );
    return Row(
      children: [
        btn(Icons.remove_rounded, () => onChanged(value - 0.5)),
        Expanded(
          child: Center(
            child: Text('${value.toStringAsFixed(1)} h',
                style: _bric(22, FontWeight.w700)),
          ),
        ),
        btn(Icons.add_rounded, () => onChanged(value + 0.5)),
      ],
    );
  }
}

Widget _grid2(List<Widget> tiles) {
  final rows = <Widget>[];
  for (var i = 0; i < tiles.length; i += 2) {
    rows.add(Padding(
      padding: EdgeInsets.only(bottom: i + 2 < tiles.length ? 9 : 0),
      child: Row(
        children: [
          Expanded(child: tiles[i]),
          const SizedBox(width: 9),
          Expanded(
              child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
        ],
      ),
    ));
  }
  return Column(children: rows);
}

class _SelectCard extends StatelessWidget {
  const _SelectCard({
    required this.label,
    required this.note,
    required this.selected,
    required this.onTap,
    this.big = false,
  });
  final String label;
  final String note;
  final bool selected;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: selected ? Cc.sage : Cc.paperRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? const Color(0x593E4A28) : const Color(0x1A15150F)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: _bric(big ? 17 : 15.5, FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(note, style: _sans(11.5, color: _note, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _CheckDot(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _CheckDot extends StatelessWidget {
  const _CheckDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Cc.oliveDark : Colors.transparent,
        border: Border.all(
            width: 2,
            color: selected ? Cc.oliveDark : const Color(0x3820241A)),
      ),
      child: selected
          ? Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Cc.sage))
          : null,
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Cc.sage : Cc.paperRaised,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: selected ? const Color(0x4D3E4A28) : const Color(0x1A15150F)),
        ),
        child: Text(
          selected ? '$label  ✓' : label,
          style: _sans(12.5,
              w: FontWeight.w500, color: selected ? Cc.inkSoft : _chipInk),
        ),
      ),
    );
  }
}

class _AllergyTile extends StatelessWidget {
  const _AllergyTile(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? _peach : Cc.paperRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? const Color(0x66D07E52) : const Color(0x1A15150F)),
        ),
        child: Row(
          children: [
            Container(
              width: 19,
              height: 19,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Cc.avoid : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    width: 1.5,
                    color: selected ? Cc.avoid : const Color(0x3820241A)),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(12.5,
                      w: FontWeight.w500,
                      color: selected ? Cc.inkSoft : _chipInk)),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow(
      {required this.title,
      required this.units,
      required this.value,
      required this.onPick});
  final String title;
  final List<String> units;
  final String value;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: _bric(14, FontWeight.w700)),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
              color: _dim, borderRadius: BorderRadius.circular(99)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final u in units)
                GestureDetector(
                  onTap: () => onPick(u),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
                    decoration: BoxDecoration(
                      color: u == value ? Cc.olive : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(u,
                        style: _sans(12,
                            w: FontWeight.w500,
                            color: u == value ? Cc.paper : Cc.muted)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BigInput extends StatelessWidget {
  const _BigInput(
      {required this.hint, required this.unit, required this.onChanged});
  final String hint;
  final String unit;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hair),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: onChanged,
              style: _bric(22, FontWeight.w700),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                hintText: hint,
                hintStyle: _bric(22, FontWeight.w700, color: const Color(0xFFB8B9A8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(unit,
              style: const TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _faint)),
        ],
      ),
    );
  }
}

class _PlainInput extends StatelessWidget {
  const _PlainInput({required this.hint, required this.onChanged});
  final String hint;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hair),
      ),
      child: TextField(
        onChanged: onChanged,
        maxLength: 120,
        style: _sans(13.5),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          counterText: '',
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          hintText: hint,
          hintStyle: _sans(13.5, color: _faint),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.bg, required this.fg, required this.text});
  final Color bg;
  final Color fg;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Text(text, style: _sans(12.5, color: fg, height: 1.5)),
    );
  }
}

class _MedTile extends StatelessWidget {
  const _MedTile({
    required this.dark,
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });
  final bool dark;
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: dark ? Cc.inkSoft : Cc.paperRaised,
          borderRadius: BorderRadius.circular(18),
          border: dark ? null : Border.all(color: _hair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: dark ? Cc.sage : Cc.oliveDark),
            const SizedBox(height: 10),
            Text(title,
                style: _bric(13.5, FontWeight.w700,
                    color: dark ? Cc.paper : Cc.ink)),
            const SizedBox(height: 3),
            Text(sub,
                style: _sans(11,
                    color: dark ? const Color(0xB3F1F0E4) : Cc.muted,
                    height: 1.3)),
          ],
        ),
      ),
    );
  }
}

class _DashedEmpty extends StatelessWidget {
  const _DashedEmpty({required this.title, required this.sub});
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(width: 1.5, color: const Color(0x3320241A)),
      ),
      child: Column(
        children: [
          Text(title, style: _sans(13.5, w: FontWeight.w500, color: Cc.muted)),
          const SizedBox(height: 5),
          Text(sub,
              textAlign: TextAlign.center,
              style: _sans(12, color: _faint, height: 1.5)),
        ],
      ),
    );
  }
}

class _RxCard extends StatelessWidget {
  const _RxCard({required this.rx, required this.onRemove});
  final RxEntry rx;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
          color: Cc.sageSoft, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Cc.paperRaised, borderRadius: BorderRadius.circular(11)),
            child: Text(rx.name.substring(0, 1),
                style: _bric(13, FontWeight.w700, color: Cc.oliveDark)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rx.name,
                    style: _sans(13.5, w: FontWeight.w500, color: Cc.inkSoft)),
                const SizedBox(height: 2),
                Text('${rx.dose} · ${rx.schedule}',
                    style: _sans(11.5, color: Cc.safe)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0x1A20241A)),
              child: const Icon(Icons.close_rounded, size: 14, color: Cc.oliveDark),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// building
// ---------------------------------------------------------------------------

class _BuildingView extends ConsumerWidget {
  const _BuildingView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    final oBuild = ref.watch(onboardingFlowProvider.select((s) => s.oBuild));
    final oError = ref.watch(onboardingFlowProvider.select((s) => s.oError));

    return CcScreen(
      background: Cc.paper,
      child: LayoutBuilder(
        builder: (context, cons) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: cons.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(34, 24, 34, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (oError == null)
                      const SizedBox(
                        width: 74,
                        height: 74,
                        child: CircularProgressIndicator(
                          strokeWidth: 5,
                          valueColor: AlwaysStoppedAnimation<Color>(Cc.olive),
                          backgroundColor: Color(0x2E63753F),
                        ),
                      )
                    else
                      Container(
                        width: 74,
                        height: 74,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                            color: _peach, shape: BoxShape.circle),
                        child: const Icon(Icons.cloud_off_rounded,
                            size: 30, color: _peachInk),
                      ),
                    const SizedBox(height: 28),
                    Text(oError == null ? 'Building your profile' : "That didn't save",
                        style: _bric(20, FontWeight.w700, height: 1.25)),
                    const SizedBox(height: 6),
                    Text(
                      oError ??
                          'Setting your ceilings and loading the interaction '
                              'rules for your medications.',
                      textAlign: TextAlign.center,
                      style: _sans(12.5, color: Cc.muted, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    for (var i = 0; i < _buildSteps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _BuildRow(
                          label: _buildSteps[i],
                          done: i < oBuild,
                          current: i == oBuild && oError == null,
                        ),
                      ),
                    if (oError != null) ...[
                      const SizedBox(height: 8),
                      _BigButton(
                        label: 'Try again',
                        bg: Cc.accent,
                        fg: Cc.inkSoft,
                        onTap: flow.retryBuilding,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BuildRow extends StatelessWidget {
  const _BuildRow(
      {required this.label, required this.done, required this.current});
  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1215150F)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? Cc.olive
                  : current
                      ? Cc.accent
                      : const Color(0x2420241A),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 13, color: Cc.paper)
                : null,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(label,
                style: _sans(13,
                    w: done || current ? FontWeight.w500 : FontWeight.w400,
                    color: done || current ? Cc.ink : _faint)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// done
// ---------------------------------------------------------------------------

class _DoneView extends ConsumerWidget {
  const _DoneView({required this.onEnterApp});
  final VoidCallback onEnterApp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    final s = ref.watch(onboardingFlowProvider);

    return CcScreen(
      background: Cc.paper,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Cc.sage, borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.check_rounded, size: 26, color: Cc.inkSoft),
          ),
          const SizedBox(height: 20),
          Text(
              s.oName.trim().isEmpty
                  ? "You're set up"
                  : "You're set up, ${s.oName.trim().split(RegExp(r'\s+')).first}",
              style: _bric(27, FontWeight.w700, height: 1.16)),
          const SizedBox(height: 10),
          Text(
            'Every label you scan from now on is checked against this profile. '
            'Nothing is generic.',
            style: _sans(13.5, color: Cc.muted, height: 1.6),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Cc.paperRaised,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x1215150F)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR PROFILE',
                    style: TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.05,
                        color: _faint)),
                const SizedBox(height: 14),
                for (final (k, v) in s.summaryRows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(k, style: _sans(12, color: Cc.muted)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(v,
                              style: _sans(12.5,
                                  w: FontWeight.w500, height: 1.45)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onEnterApp,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: Cc.sage, borderRadius: BorderRadius.circular(22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('First scan, right now',
                      style: _bric(14, FontWeight.w700, color: Cc.inkSoft)),
                  const SizedBox(height: 6),
                  Text(
                    'Your profile is live. Head to the scanner and check the '
                    'first thing you pick up.',
                    style: _sans(12.5, color: Cc.oliveDark, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: flow.restart,
            child: Container(
              padding: const EdgeInsets.all(14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Cc.paperRaised,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x1F15150F)),
              ),
              child: Text('Run the walkthrough again',
                  style: _sans(13.5, w: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton(
      {required this.label, required this.bg, required this.fg, this.onTap});
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Text(label, style: _sans(14.5, w: FontWeight.w500, color: fg)),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton(
      {required this.label, required this.dark, required this.onTap});
  final String label;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: dark ? Cc.inkSoft : Cc.paperRaised,
          borderRadius: BorderRadius.circular(16),
          border: dark ? null : Border.all(color: const Color(0x2415150F)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: dark ? Cc.paper : Cc.muted),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(14,
                      w: FontWeight.w500, color: dark ? Cc.paper : Cc.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Divider(color: _hair, height: 1)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('OR',
                style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.6,
                    color: _faint)),
          ),
          Expanded(child: Divider(color: _hair, height: 1)),
        ],
      ),
    );
  }
}
