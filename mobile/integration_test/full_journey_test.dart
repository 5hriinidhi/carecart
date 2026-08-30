// End-to-end journey through the ACTUAL UI against a locally running backend
// (http://localhost:8000):
//
//   sign up (phone → OTP) → onboarding (6 profile steps, incl. a tree-nut
//   allergy) → barcode scan → product facts → delete account → back at sign-in
//
// NOTE: the personalised "how good is this for you" verdict — and the history /
// trends / nudge data that a scored scan feeds — is deferred until the
// medicines + lifestyle correlation score lands. Until then a scan stops at the
// product's facts (name, brand, nutrition per 100 g, ingredients), so this
// journey asserts that, not a verdict. See MainApp.scanBarcode (dormant).
//
// Prereqs (the CI job wires these up):
//   * backend on :8000, ENVIRONMENT=development (so request-otp echoes the code)
//   * `python -m scripts.load_risk_tables` has run
//   * `python -m scripts.seed_demo_products` has run (barcodes 20000000001-3)
//
// Run:  flutter test integration_test/full_journey_test.dart

import 'package:carecart/main.dart' as app;
import 'package:carecart/src/features/app_shell.dart';
import 'package:carecart/src/features/home/home_screen.dart';
import 'package:carecart/src/features/onboarding/onboarding_screen.dart';
import 'package:carecart/src/features/product/product_screen.dart';
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

  testWidgets('full journey: signup → onboarding → scan → product facts → '
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

    // ---- onboarding: name + 6 profile steps ----
    await _pumpUntil(tester, find.text('A few things about you'),
        reason: 'profile step 1');
    await tester.enterText(find.byType(TextField), 'Journey');
    await tester.pump();
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
    // greeted by the name entered in onboarding, not a hardcoded persona
    expect(find.textContaining('Journey'), findsWidgets);

    // ---- scan a seeded product → real facts from GET /products/{barcode} ----
    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    await _pumpUntil(tester, find.byKey(const Key('scan-barcode-field')),
        reason: 'scan screen');
    await tester.enterText(
        find.byKey(const Key('scan-barcode-field')), _cashewBarcode);
    await tester.tap(find.byKey(const Key('scan-barcode-submit')));

    await _pumpUntil(tester, find.byType(ProductScreen),
        timeout: const Duration(seconds: 25), reason: 'product facts screen');
    expect(find.text('Roasted Cashew Bar'), findsOneWidget);
    expect(find.text('Barcode $_cashewBarcode'), findsOneWidget);
    expect(find.text('Nutrition'), findsOneWidget);
    // no personal verdict is shown yet
    expect(find.text('CARECART SCORE /100'), findsNothing);
    expect(find.textContaining("isn't scoring it against"), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await _pumpUntil(tester, find.byType(HomeScreen), reason: 'home after scan');

    // ---- an unknown barcode never shows a product: it stays on the scan
    //      screen with a banner, it does not open ProductScreen ----
    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    await _pumpUntil(tester, find.byKey(const Key('scan-barcode-field')),
        reason: 'scan screen again');
    await tester.enterText(
        find.byKey(const Key('scan-barcode-field')), '19999999999999');
    await tester.tap(find.byKey(const Key('scan-barcode-submit')));
    // give the lookup time to resolve either way
    await tester.pump(const Duration(seconds: 8));
    expect(find.byType(ProductScreen), findsNothing,
        reason: 'an unknown barcode must never render a product');
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
