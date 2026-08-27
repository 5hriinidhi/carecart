import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carecart/src/app.dart';

void main() {
  testWidgets('app boots to onboarding', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CareCartApp()));
    await tester.pumpAndSettle();
    expect(find.text('CareCart'), findsOneWidget);
  });
}
