// Step 2 — a real barcode scan shows the product's facts (name, brand, nutrition
// per 100 g, ingredients) and NOT a personal verdict; the demo product picker is
// dev-only so a tap can never masquerade as a scan.

import 'package:carecart/src/core/product_api.dart';
import 'package:carecart/src/features/product/product_screen.dart';
import 'package:carecart/src/features/scan/scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _poha = ScannedProduct(
  barcode: '8901058000108',
  name: 'Poha (Flattened Rice)',
  brand: 'Local Mills',
  ingredients: ['Flattened rice (poha)'],
  ingredientsText: 'Flattened rice (poha)',
  nutriments: {
    'energy_kcal_100g': 346,
    'carbohydrates_g_100g': 77.3,
    'sodium_mg_100g': 6,
  },
  servingSize: '40 g',
  cached: true,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(430, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('product screen shows real name, brand, nutrition + ingredients',
      (tester) async {
    await _pump(tester, const ProductScreen(product: _poha));

    expect(find.text('Poha (Flattened Rice)'), findsOneWidget);
    expect(find.text('Local Mills'), findsOneWidget);
    expect(find.text('Barcode 8901058000108'), findsOneWidget);

    // nutrition table, per 100 g, values formatted (int vs 1-dp)
    expect(find.text('PER 100 G'), findsOneWidget);
    expect(find.text('346 kcal'), findsOneWidget);
    expect(find.text('77.3 g'), findsOneWidget);
    expect(find.text('6 mg'), findsOneWidget);
    expect(find.textContaining('Serving size'), findsOneWidget);

    // ingredients
    expect(find.text('Flattened rice (poha)'), findsWidgets);
  });

  testWidgets('product screen shows NO CareCart score / verdict yet',
      (tester) async {
    await _pump(tester, const ProductScreen(product: _poha));

    expect(find.text('CARECART SCORE /100'), findsNothing);
    expect(find.text('Why this verdict'), findsNothing);
    expect(find.textContaining("isn't scoring it against"), findsOneWidget);
  });

  testWidgets('missing nutrition / ingredients degrade to a clear note',
      (tester) async {
    await _pump(
      tester,
      const ProductScreen(
        product: ScannedProduct(barcode: '00000000', name: 'Mystery Item'),
      ),
    );

    expect(find.text('Mystery Item'), findsOneWidget);
    expect(find.textContaining("doesn't list nutrition values"), findsOneWidget);
    expect(find.textContaining('No ingredient list on file'), findsOneWidget);
  });

  testWidgets('scan screen hides the demo picker unless it is turned on',
      (tester) async {
    await _pump(
      tester,
      const ScanScreen(cameraEnabled: false, showDemoPicker: false),
    );
    expect(find.text('DEMO — PICK A PRODUCT TO SCAN'), findsNothing);
    expect(find.text('Instant Masala Noodles'), findsNothing);
    // manual entry is still there
    expect(find.byKey(const Key('scan-barcode-field')), findsOneWidget);

    await _pump(
      tester,
      const ScanScreen(cameraEnabled: false, showDemoPicker: true),
    );
    expect(find.text('DEMO — PICK A PRODUCT TO SCAN'), findsOneWidget);
  });
}
