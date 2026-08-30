// Step 3b — "Look it up": search the everyday-food dataset and open a food's
// facts. Search-only; no camera, no verdict yet.

import 'package:carecart/src/core/foods_api.dart';
import 'package:carecart/src/features/facts/food_screen.dart';
import 'package:carecart/src/features/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

final _foods = [
  const FoodHit(
    name: 'Poha',
    kind: 'dish',
    ingredientsText: 'Flattened rice, peanuts, onion, curry leaves',
    diet: 'vegetarian',
    course: 'snack',
    region: 'West',
  ),
  const FoodHit(
    name: 'Hide & Seek',
    kind: 'packaged',
    brand: 'Parle',
    category: 'BISCUIT / COOKIES',
    ingredientsText: 'Refined wheat flour, sugar, cocoa solids',
    servingSize: '100 g',
    nutriments: {'energy_kcal_100g': 479.0, 'sugars_g_100g': 32.5},
  ),
];

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: fakeBackendOverrides(foods: FakeFoodsApi(hits: _foods)),
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: SearchScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('idle hint -> type -> results -> open a dish', (tester) async {
    await _pump(tester);
    expect(find.textContaining('Type a dish or product name'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('food-search-field')), 'poha');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Poha'), findsOneWidget);
    expect(find.text('DISH'), findsWidgets);

    await tester.tap(find.text('Poha'));
    await tester.pumpAndSettle();

    expect(find.byType(FoodScreen), findsOneWidget);
    expect(find.text('HOME DISH'), findsOneWidget);
    expect(find.text('VEGETARIAN'), findsOneWidget);
    expect(find.textContaining('Flattened rice'), findsOneWidget);
    // a dish carries no nutrition panel
    expect(find.textContaining('not a per-100 g nutrition panel'), findsOneWidget);
    // no personal verdict yet
    expect(find.textContaining("isn't scoring this"), findsOneWidget);
  });

  testWidgets('a packaged hit shows its per-100 g panel', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('food-search-field')), 'hide');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide & Seek'));
    await tester.pumpAndSettle();

    expect(find.text('PACKAGED FOOD'), findsOneWidget);
    expect(find.text('PER 100 G'), findsOneWidget);
    expect(find.text('479 kcal'), findsOneWidget);
    expect(find.text('32.5 g'), findsOneWidget);
  });

  testWidgets('no matches -> a clear message, not a dead end', (tester) async {
    await _pump(tester);
    await tester.enterText(
        find.byKey(const Key('food-search-field')), 'zzznope');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('No food matched that'), findsOneWidget);
  });

  testWidgets('a one-letter query makes no request', (tester) async {
    final fake = FakeFoodsApi(hits: _foods);
    final container = ProviderContainer(
      overrides: fakeBackendOverrides(foods: fake),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SearchScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('food-search-field')), 'p');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(fake.queries, isEmpty);
    expect(find.textContaining('Type a dish or product name'), findsOneWidget);
  });
}
