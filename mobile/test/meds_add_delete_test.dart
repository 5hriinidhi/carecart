// Step 3 — add a medication from the searchable catalogue, and delete one, both
// gated by the on-device PIN.

import 'package:carecart/src/core/drugs_api.dart';
import 'package:carecart/src/core/pin_lock.dart';
import 'package:carecart/src/features/meds/meds_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

final _catalogue = [
  const DrugHit(
      name: 'Telma 40 Tablet',
      saltComposition: 'Telmisartan (40mg)',
      activeIngredients: 'telmisartan'),
  const DrugHit(
      name: 'Ecosprin 75 Tablet',
      saltComposition: 'Aspirin (75mg)',
      activeIngredients: 'aspirin'),
];

Future<ProviderContainer> _pumpMeds(WidgetTester tester,
    {FakeVaultApi? vault}) async {
  tester.view.physicalSize = const Size(430, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: fakeBackendOverrides(
      vault: vault,
      drugs: FakeDrugsApi(hits: _catalogue),
    ),
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: MedsScreen())),
  ));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _searchAndPick(WidgetTester tester, String query, String name) async {
  await tester.tap(find.byKey(const Key('meds-add-button')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('med-search-field')), query);
  await tester.pump(const Duration(milliseconds: 350)); // debounce
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> _enterPin(WidgetTester tester, String pin,
    {bool create = false}) async {
  await tester.enterText(find.byKey(const Key('pin-field')), pin);
  if (create) {
    await tester.enterText(find.byKey(const Key('pin-confirm-field')), pin);
  }
  await tester.tap(find.byKey(const Key('pin-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first add: search -> pick -> create a PIN -> saved', (tester) async {
    final vault = FakeVaultApi();
    final container = await _pumpMeds(tester, vault: vault);

    expect(find.byKey(const Key('meds-note')), findsOneWidget); // empty state

    await _searchAndPick(tester, 'telma', 'Telma 40 Tablet');
    await tester.enterText(
        find.byKey(const Key('med-dosage-field')), '40 mg once daily');
    await tester.tap(find.byKey(const Key('med-add-confirm')));
    await tester.pumpAndSettle();

    // no PIN yet -> the dialog is in "create" mode
    expect(find.text('Set a medications PIN'), findsOneWidget);
    await _enterPin(tester, '4271', create: true);

    expect(vault.medications.single.name, 'Telma 40 Tablet');
    expect(vault.medications.single.dosage, '40 mg once daily');
    expect(find.descendant(
          of: find.byKey(const Key('meds-list')),
          matching: find.text('Telma 40 Tablet')),
        findsOneWidget);
    expect(await container.read(pinLockProvider).isSet(), isTrue);
  });

  testWidgets('a wrong PIN blocks the delete; the right one removes it',
      (tester) async {
    final vault = FakeVaultApi()..medications.add((name: 'Telma 40 Tablet', dosage: null));
    final container = await _pumpMeds(tester, vault: vault);
    await container.read(pinLockProvider).setPin('4271');

    expect(find.text('Telma 40 Tablet'), findsOneWidget);

    // wrong PIN 3x -> dialog gives up, med stays
    await tester.tap(find.byKey(const Key('med-delete-Telma 40 Tablet')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await _enterPin(tester, '0000');
    }
    expect(vault.medications, isNotEmpty);
    expect(find.text('Telma 40 Tablet'), findsOneWidget);

    // right PIN -> gone
    await tester.tap(find.byKey(const Key('med-delete-Telma 40 Tablet')));
    await tester.pumpAndSettle();
    await _enterPin(tester, '4271');
    expect(vault.medications, isEmpty);
    expect(find.text('Telma 40 Tablet'), findsNothing);
  });

  testWidgets('a too-short search makes no request and shows nothing',
      (tester) async {
    await _pumpMeds(tester);
    await tester.tap(find.byKey(const Key('meds-add-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('med-search-field')), 'e');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Telma 40 Tablet'), findsNothing);
    expect(find.text('Ecosprin 75 Tablet'), findsNothing);
  });
}
