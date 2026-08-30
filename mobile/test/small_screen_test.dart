// Edge case: the design canvas is 428x908. Verify every screen also lays out
// without overflow on smaller / older phones — 360x640 and a very tight
// 320x568 (iPhone SE 1st gen, budget Androids) — including the cramped
// onboarding steps.
//
//   flutter test test/small_screen_test.dart -r expanded

import 'package:carecart/src/debug/debug_gallery.dart';
import 'package:carecart/src/features/onboarding/onboarding_screen.dart';
import 'package:carecart/src/state/onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

const _sizes = <Size>[Size(360, 640), Size(320, 568)];

Future<Object?> _scrollThrough(WidgetTester tester) async {
  Object? firstError = tester.takeException();
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isEmpty) return firstError;
  for (var i = 0; i < 16; i++) {
    firstError ??= tester.takeException();
    await tester.drag(scrollable.first, const Offset(0, -350));
    await tester.pump(const Duration(milliseconds: 40));
  }
  firstError ??= tester.takeException();
  return firstError;
}

void main() {
  for (final entry in debugScreens.entries) {
    for (final size in _sizes) {
      testWidgets('${entry.key} @ ${size.width.toInt()}x${size.height.toInt()} — no overflow',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(ProviderScope(
          overrides: fakeBackendOverrides(),
          child: MaterialApp(
              home: Scaffold(body: Builder(builder: entry.value.build))),
        ));
        await tester.pump(const Duration(milliseconds: 300));

        final err = await _scrollThrough(tester);
        expect(err, isNull,
            reason: '${entry.key} @ ${size.width.toInt()}w threw a layout exception');
      });
    }
  }

  // Onboarding — walk each of the 6 profile steps at the tightest size and
  // confirm none overflow (6 select cards, a 2-col allergy grid, unit toggles).
  for (final size in _sizes) {
    testWidgets('onboarding all steps @ ${size.width.toInt()}x${size.height.toInt()} — no overflow',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final flow = container.read(onboardingFlowProvider.notifier);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OnboardingScreen(onComplete: _noop)),
      ));

      Future<void> check(String where) async {
        await tester.pump(const Duration(milliseconds: 100));
        final scroll = find.byType(Scrollable);
        if (scroll.evaluate().isNotEmpty) {
          await tester.drag(scroll.first, const Offset(0, -400));
          await tester.pump(const Duration(milliseconds: 40));
          await tester.drag(scroll.first, const Offset(0, 800));
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(tester.takeException(), isNull, reason: 'overflow at $where');
      }

      await check('login');
      flow.submitPhone();
      await check('otp');
      flow.skipAuth();
      for (var i = 0; i < 6; i++) {
        await check('step ${i + 1} (${flow.state.oStepKind.name})');
        if (i == 5) {
          flow.scanRx(); // meds step: render the Rx list too
          await check('step 6 with Rx list');
        }
        if (i < 5) flow.next();
      }
      flow.startBuilding();
      await check('building');
      await tester.pump(const Duration(milliseconds: 2700));
      await check('done');
      await tester.pump(const Duration(milliseconds: 1600)); // drain auto-handoff timer
    });
  }
}

void _noop() {}
