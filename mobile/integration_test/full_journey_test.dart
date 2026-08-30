// End-to-end journey through the ACTUAL UI against a locally running backend
// (http://localhost:8000):
//
//   sign up (phone → OTP) → onboarding (7 profile steps, incl. a tree-nut
//   allergy + a poor lifestyle) → barcode scan → personalised verdict →
//   history → delete account → back at sign-in
//
// Prereqs (the CI job wires these up):
//   * backend on :8000, ENVIRONMENT=development (so request-otp echoes the code)
//   * `python -m scripts.load_risk_tables` has run
//   * `python -m scripts.load_drug_catalog` / `load_food_catalog` have run
//   * `python -m scripts.seed_demo_products` has run (barcodes 20000000001-3)
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
      'account deletion', (tester) async {
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

    // ---- onboarding: name + 7 profile steps ----
    await _pumpUntil(tester, find.text('A few things about you'),
        reason: 'profile step 1');
    await tester.enterText(find.byType(TextField), 'Journey');
    await tester.pump();
    await tester.tap(find.text('Male'));
    await tester.pump();
    await tester.tap(find.text('Next'));

    await _pumpUntil(tester, find.text('How many days a week are you active?'));
    await tester.tap(find.text('2 days'));
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
    await tester.tap(find.text('Next'));

    await _pumpUntil(tester, find.text('A little about your lifestyle'));
    await tester.tap(find.text('Daily'));   // smoking
    await tester.pump();
    await tester.tap(find.text('5'));       // stress -> lifestyle penalties kick in
    await tester.pump();
    await tester.tap(find.text('Complete'));

    // ---- building (real vault writes) → done → auto-handoff → home ----
    await _pumpUntil(tester, find.byType(HomeScreen),
        timeout: const Duration(seconds: 30), reason: 'main app home');
    expect(find.byType(OnboardingScreen), findsNothing);
    // greeted by the name entered in onboarding, not a hardcoded persona
    expect(find.textContaining('Journey'), findsWidgets);

    // ---- scan a seeded tree-nut product → allergen hard-stop verdict ----
    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    await _pumpUntil(tester, find.byKey(const Key('scan-barcode-field')),
        reason: 'scan screen');
    await tester.enterText(
        find.byKey(const Key('scan-barcode-field')), _cashewBarcode);
    await tester.tap(find.byKey(const Key('scan-barcode-submit')));

    await _pumpUntil(tester, find.byType(ResultScreen),
        timeout: const Duration(seconds: 25), reason: 'verdict result screen');
    expect(tester.widget<Text>(find.byKey(const Key('verdict-tier'))).data,
        'Avoid',
        reason: 'tree-nut allergen is a hard stop');
    expect(find.textContaining(RegExp('nut', caseSensitive: false)), findsWidgets);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await _pumpUntil(tester, find.byType(HomeScreen), reason: 'home after scan');

    // ---- history: the scan was logged automatically by /scan/verdict ----
    await tester.tap(find.text('History'));
    await _pumpUntil(tester, find.text('Roasted Cashew Bar'),
        reason: 'history row for the scanned product');
    await tester.tap(find.text('Home'));
    await _pumpUntil(tester, find.byType(HomeScreen));

    // ---- an unknown barcode stays on the scan screen with a banner ----
    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    await _pumpUntil(tester, find.byKey(const Key('scan-barcode-field')),
        reason: 'scan screen again');
    await tester.enterText(
        find.byKey(const Key('scan-barcode-field')), '19999999999999');
    await tester.tap(find.byKey(const Key('scan-barcode-submit')));
    await tester.pump(const Duration(seconds: 8));
    expect(find.byType(ResultScreen), findsNothing,
        reason: 'an unknown barcode must never produce a verdict');
    expect(find.byKey(const Key('scan-barcode-field')), findsOneWidget,
        reason: 'still on the scan screen');
    await tester.tap(find.text('Home'));
    await _pumpUntil(tester, find.byType(HomeScreen));

    // ---- account deletion: hard delete + back to sign-in ----
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
