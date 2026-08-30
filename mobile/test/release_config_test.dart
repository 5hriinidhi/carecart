// Phase 6.4 — the judge / release build exposes no dev-only surfaces.

import 'package:carecart/src/app.dart';
import 'package:carecart/src/core/build_config.dart';
import 'package:carecart/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

List<String> _paths(RouteBase r) => [
      if (r is GoRoute) r.path,
      for (final c in r.routes) ..._paths(c),
    ];

void main() {
  test('release build: the /debug screen gallery route is NOT registered', () {
    final c = ProviderContainer(
        overrides: [debugGalleryEnabledProvider.overrideWithValue(false)]);
    addTearDown(c.dispose);

    final router = c.read(routerProvider);
    final allPaths =
        router.configuration.routes.expand(_paths).toList();
    expect(allPaths, isNot(contains('/debug')));
    expect(allPaths, containsAll(['/onboarding', '/app']));
  });

  test('dev build: the /debug route IS available when explicitly enabled', () {
    final c = ProviderContainer(
        overrides: [debugGalleryEnabledProvider.overrideWithValue(true)]);
    addTearDown(c.dispose);
    final allPaths = c
        .read(routerProvider)
        .configuration
        .routes
        .expand(_paths)
        .toList();
    expect(allPaths, contains('/debug'));
  });

  testWidgets('navigating to /debug in a release build never dead-ends',
      (tester) async {
    final c = ProviderContainer(
        overrides: [debugGalleryEnabledProvider.overrideWithValue(false)]);
    addTearDown(c.dispose);
    final router = c.read(routerProvider);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    router.go('/debug');
    await tester.pumpAndSettle();

    // redirected away, no GoRouter error page
    expect(find.textContaining('Page Not Found'), findsNothing);
    expect(find.textContaining('no routes for location'), findsNothing);
    expect(router.state.uri.path, anyOf('/onboarding', '/app'));
  });

  testWidgets('no debug banner on any MaterialApp', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CareCartApp()));
    await tester.pump(); // splash
    await tester.pumpAndSettle();

    final apps = tester.widgetList<MaterialApp>(find.byType(MaterialApp));
    expect(apps, isNotEmpty);
    for (final a in apps) {
      expect(a.debugShowCheckedModeBanner, isFalse);
    }
  });

  test('demo-mode chip is off by default (only on with --dart-define)', () {
    // kDemoMode is a compile-time constant; the test process has no dart-define
    expect(kDemoMode, isFalse);
  });
}
