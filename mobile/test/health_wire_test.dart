// Phase 1 -> 2 wire check, part B: the real HomeScreen widget renders a
// /health response on screen.
//
// The HTTP call itself is exercised by `dart run tool/health_probe.dart`
// (part A) - real dio -> real backend. Here we feed HomeScreen the same
// HealthResult shape the backend returns and assert the screen displays it,
// so the render path is proven without a flaky network call inside flutter_test.
//
//   flutter test test/health_wire_test.dart

import 'package:carecart/src/core/api_client.dart';
import 'package:carecart/src/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HomeScreen shows a successful /health result as "wire is live"',
      (tester) async {
    // exactly what `GET /health` returns from the running backend
    const backendResponse = HealthResult(
      reachable: true,
      httpStatus: 200,
      body: {'status': 'ok', 'db': 'connected'},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthCheckProvider.overrideWith((ref) async => backendResponse),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('health-status'));
    expect(card, findsOneWidget);

    final rendered = tester
        .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
        .map((t) => t.data)
        .whereType<String>()
        .join('  |  ');
    // ignore: avoid_print
    print('RENDERED ON SCREEN:  $rendered');

    expect(find.text('wire is live'), findsOneWidget);
    expect(rendered, contains('HTTP 200'));
    expect(rendered, contains('status=ok'));
    expect(rendered, contains('db=connected'));
  });

  testWidgets('HomeScreen shows a failure clearly when the backend is down',
      (tester) async {
    const down = HealthResult(
      reachable: false,
      httpStatus: null,
      body: {'error': 'Connection refused'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [healthCheckProvider.overrideWith((ref) async => down)],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('no connection'), findsOneWidget);
    expect(find.text('wire is live'), findsNothing);
  });
}
