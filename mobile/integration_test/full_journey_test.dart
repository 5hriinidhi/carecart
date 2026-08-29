// Phase 6.1 — end-to-end journey through the ACTUAL UI against a locally
// running backend (http://localhost:8000):
//
//   sign up (phone → OTP) → onboarding (6 profile steps, incl. a tree-nut
//   allergy) → barcode scan → verdict → history → trends → nudge →
//   delete account → back at sign-in
//
// Prereqs (the CI job wires these up):
//   * backend on :8000, ENVIRONMENT=development (so request-otp echoes the code)
//   * `python -m scripts.load_risk_tables` has run
//   * `python -m scripts.seed_demo_products` has run (barcodes 200000000010-3)
//
// Run:  flutter test integration_test/full_journey_test.dart

import 'package:carecart/main.dart' as app;
import 'package:carecart/src/features/app_shell.dart';
import 'package:carecart/src/features/home/home_screen.dart';
import 'package:carecart/src/features/onboarding/onboarding_screen.dart';
import 'package:carecart/src/features/result/result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _cashewBarcode = '20000000001'; // Roasted Cashew Bar (seeded)

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for: ${reason ?? finder.toString()}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full journey: signup → onboarding → scan → verdict → history → '
      'trends → nudge → account deletion', (tester) async {
    // a fresh phone number per run so it is always a brand-new account
    final phone = '9${DateTime.now().millisecondsSinceEpoch.toString().substring(4, 13)}';

    app.main();
    await _pumpUntil(tester, find.text('CareCart'), reason: 'sign-in screen');

    // ---- sign up: phone → request-otp ----
    await tester.enterText(find.byType(TextField).first, phone);
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _pumpUntil(tester, find.text('Enter the code'), reason: 'OTP screen');

    // a dev backend echoes the code; the flow stages it into the boxes
    await _pumpUntil(tester, find.text('Verified — continue'),
        reason: 'dev OTP code auto-filled');
    await tester.tap(find.text('Verified — continue'));

    // ---- onboarding: 6 profile steps ----
    await _pumpUntil(tester, find.text('A few things about you'),
        reason: 'profile step 1');
    await tester.tap(find.text('Male'));
    await tester.pump();
    await tester.tap(find.text('Next'));

    await _pumpUntil(tester, find.text('How active is a normal week?'));
    await tester.tap(find.text('Sedentary'));
    await tester.pump();
    await tester.tap(find.text('Next'));

    await _pumpUntil(tester, find.text('Your measurements'));
    await tester.tap(find.text('Next'));

    await _pumpUntil(tester, find.text('Any dietary preferences?'));
    await tester.tap(find.text('Next'));

    await _pumpUntil(tester, find.text('Anything you must avoid?'));
    await tester.tap(find.text('Tree nuts'));
    await tester.pump();
    await tester.tap(find.text('Next'));

    await _pumpUntil(tester, find.text('What are you taking?'));
    await tester.tap(find.text('Complete'));

    // ---- building (real vault writes) → done → auto-handoff → home ----
    await _pumpUntil(tester, find.byType(HomeScreen),
        timeout: const Duration(seconds: 30), reason: 'main app home');
    expect(find.byType(OnboardingScreen), findsNothing);

    // ---- scan the tree-nut product 3× (allergen hard-stop + a recurring
    //      pattern that trips the nudge engine on the 3rd) ----
    for (var i = 1; i <= 3; i++) {
      await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
      await _pumpUntil(tester, find.byKey(const Key('scan-barcode-field')),
          reason: 'scan screen (pass $i)');
      await tester.enterText(
          find.byKey(const Key('scan-barcode-field')), _cashewBarcode);
      await tester.tap(find.byKey(const Key('scan-barcode-submit')));

      await _pumpUntil(tester, find.byType(ResultScreen),
          timeout: const Duration(seconds: 25), reason: 'verdict result (pass $i)');
      expect(
        tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data,
        'Avoid',
        reason: 'tree-nut allergen must be a hard stop',
      );
      if (i == 1) {
        // the reason names the actual conflict, not a generic message
        expect(find.textContaining(RegExp('nut', caseSensitive: false)),
            findsWidgets);
      }
      await tester.tap(find.byIcon(Icons.close_rounded));
      await _pumpUntil(tester, find.byType(HomeScreen), reason: 'home (pass $i)');
    }

    // ---- history: the scans are logged automatically ----
    await tester.tap(find.text('History'));
    await _pumpUntil(tester, find.text('Roasted Cashew Bar'),
        reason: 'history row for the scanned product');
    expect(find.text('Food history'), findsOneWidget);

    // ---- trends: the diet health score renders ----
    await tester.tap(find.text('Trend'));
    await _pumpUntil(tester, find.byKey(const Key('dhs-value')),
        reason: 'diet health score');

    // ---- nudge: the recurring tree-nut pattern produced one ----
    await tester.tap(find.text('Home'));
    await _pumpUntil(tester, find.byType(HomeScreen));
    await tester.tap(find.text("What's driving it"));
    await _pumpUntil(tester, find.byKey(const Key('nudge-message')),
        reason: 'nudge screen message');
    final nudgeMsg =
        tester.widget<Text>(find.byKey(const Key('nudge-message'))).data ?? '';
    expect(nudgeMsg.length, greaterThan(20),
        reason: 'a specific, actionable nudge — not an empty / generic screen');

    // ---- account deletion: hard delete + back to sign-in ----
    await tester.tap(find.text('Home'));
    await _pumpUntil(tester, find.byType(HomeScreen));
    await tester.tap(find.byKey(const Key('home-profile-button')));
    await _pumpUntil(tester, find.byKey(const Key('profile-delete-account')));
    await tester.tap(find.byKey(const Key('profile-delete-account')));
    await _pumpUntil(tester, find.byKey(const Key('profile-delete-confirm')),
        reason: 'delete confirmation dialog');
    await tester.tap(find.byKey(const Key('profile-delete-confirm')));

    await _pumpUntil(tester, find.byType(OnboardingScreen),
        timeout: const Duration(seconds: 25),
        reason: 'returned to sign-in after deletion');
    expect(find.byType(MainAppShell), findsNothing);
  });
}
