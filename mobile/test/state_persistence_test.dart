// Edge case: app state must survive a device rotation and an app
// background/resume — i.e. the Riverpod providers are app-lifetime singletons
// under the single root ProviderScope, not scoped below a route or marked
// autoDispose.
//
//   flutter test test/state_persistence_test.dart -r expanded

import 'package:carecart/src/app.dart';
import 'package:carecart/src/core/analytics_api.dart';
import 'package:carecart/src/features/app_shell.dart';
import 'package:carecart/src/features/trends/trends_screen.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:carecart/src/state/onboarding_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

/// login -> otp -> steps, through the real flow against in-memory fakes.
Future<void> _signIn(ProviderContainer c, WidgetTester tester) async {
  final f = c.read(onboardingFlowProvider.notifier);
  f.setPhone('9876543210');
  await f.submitPhone();
  f.setOtp('123456');
  await f.verifyOtp();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('onboarding progress survives rotation + background/resume',
      (tester) async {
    tester.view.physicalSize = const Size(430, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
        overrides: fakeBackendOverrides(auth: FakeAuthApi(devCode: '123456')));
    addTearDown(container.dispose);
    final onbNotifier = container.read(onboardingFlowProvider.notifier);
    OnboardingState onb() => container.read(onboardingFlowProvider);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CareCartApp(),
    ));
    await tester.pumpAndSettle();

    await _signIn(container, tester);

    // walk a few steps into the wizard and record some choices
    onbNotifier.setGender('Female');
    await onbNotifier.next(); // -> activity
    onbNotifier.setActivity('Heavy');
    await onbNotifier.next(); // -> body
    await tester.pumpAndSettle();

    expect(onb().oScreen, OnbScreen.steps);
    expect(onb().oStep, 2);
    expect(find.text('Your measurements'), findsOneWidget);

    // ---- rotate to landscape ----
    tester.view.physicalSize = const Size(920, 430);
    await tester.pumpAndSettle();
    expect(onb().oScreen, OnbScreen.steps, reason: 'screen kept across rotation');
    expect(onb().oStep, 2, reason: 'step index kept across rotation');
    expect(onb().oGender, 'Female');
    expect(onb().oActivity, 'Heavy');
    expect(find.text('Your measurements'), findsOneWidget);

    // ---- rotate back to portrait ----
    tester.view.physicalSize = const Size(430, 920);
    await tester.pumpAndSettle();
    expect(onb().oStep, 2);

    // ---- background then resume ----
    for (final st in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(st);
    }
    await tester.pump();
    for (final st in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(st);
    }
    await tester.pumpAndSettle();

    expect(onb().oScreen, OnbScreen.steps, reason: 'screen kept across background/resume');
    expect(onb().oStep, 2, reason: 'step kept across background/resume');
    expect(onb().oGender, 'Female');
    expect(onb().oActivity, 'Heavy');
    expect(find.text('Your measurements'), findsOneWidget);
  });

  testWidgets('main-app tab + scroll survive rotation after handoff', (tester) async {
    tester.view.physicalSize = const Size(430, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: fakeBackendOverrides(
        auth: FakeAuthApi(devCode: '123456'),
        trends: const TrendsLoaded(Trends(
            timezone: 'UTC', totalScans: 0, dietHealthScore: 0,
            deltaSevenDay: 0, trend: 'steady')),
      ),
    );
    addTearDown(container.dispose);
    MainAppState app() => container.read(mainAppProvider);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CareCartApp(),
    ));
    await tester.pumpAndSettle();

    await _signIn(container, tester);

    // fast-forward the wizard to done, then hand off to /app
    final onb = container.read(onboardingFlowProvider.notifier);
    for (var i = 0; i < kOnbSteps.length; i++) {
      await onb.next();
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1600)); // auto-handoff beat
    await tester.pumpAndSettle();

    expect(find.byType(MainAppShell), findsOneWidget);

    container.read(mainAppProvider.notifier).goTab(MainScreen.trends);
    await tester.pumpAndSettle();
    expect(app().tab, MainScreen.trends);
    final scrollable = find.descendant(
        of: find.byType(TrendsScreen), matching: find.byType(Scrollable));
    await tester.drag(scrollable, const Offset(0, -260));
    await tester.pump();
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offset, greaterThan(80));

    tester.view.physicalSize = const Size(920, 430);
    await tester.pumpAndSettle();
    expect(app().screen, MainScreen.trends, reason: 'tab kept across rotation');
    expect(app().tab, MainScreen.trends);
    expect(find.byType(TrendsScreen), findsOneWidget);

    tester.view.physicalSize = const Size(430, 920);
    await tester.pumpAndSettle();
    expect(app().tab, MainScreen.trends);
    expect(tester.state<ScrollableState>(scrollable).position.pixels,
        moreOrLessEquals(offset, epsilon: 1),
        reason: 'Trends scroll offset survived rotation');
  });

  test('core providers are not autoDispose (state outlives listener removal)', () {
    final c = ProviderContainer(overrides: fakeBackendOverrides());
    addTearDown(c.dispose);

    c.read(mainAppProvider.notifier).goTab(MainScreen.meds);
    c.read(onboardingFlowProvider.notifier).setPhone('9876500000');

    // a one-shot read adds then drops a listener; autoDispose would reset here
    c.read(mainAppProvider);
    c.read(onboardingFlowProvider);

    expect(c.read(mainAppProvider).tab, MainScreen.meds);
    expect(c.read(onboardingFlowProvider).oPhone, '9876500000');
  });
}
