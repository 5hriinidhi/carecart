// Edge case: app state must survive a device rotation and an app
// background/resume — i.e. the Riverpod providers are app-lifetime singletons
// under the single root ProviderScope, not scoped below a route or marked
// autoDispose.
//
//   flutter test test/state_persistence_test.dart -r expanded

import 'package:carecart/src/app.dart';
import 'package:carecart/src/features/app_shell.dart';
import 'package:carecart/src/features/trends/trends_screen.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:carecart/src/state/onboarding_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('onboarding progress survives rotation + background/resume',
      (tester) async {
    tester.view.physicalSize = const Size(430, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final onbNotifier = container.read(onboardingFlowProvider.notifier);
    OnboardingState onb() => container.read(onboardingFlowProvider);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CareCartApp(),
    ));
    await tester.pumpAndSettle();

    // walk a few steps into the wizard and record some choices
    onbNotifier.skipAuth();
    onbNotifier.setGender('Female');
    onbNotifier.next(); // -> activity
    onbNotifier.setActivity('Heavy');
    onbNotifier.next(); // -> body
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

    // ---- background then resume (stepping through the valid lifecycle chain) ----
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

    final container = ProviderContainer();
    addTearDown(container.dispose);
    MainAppState app() => container.read(mainAppProvider);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CareCartApp(),
    ));
    await tester.pumpAndSettle();

    // fast-forward onboarding to done, then hand off to /app
    final onb = container.read(onboardingFlowProvider.notifier);
    onb.skipAuth();
    for (var i = 0; i < 6; i++) {
      onb.next();
    }
    await tester.pump(const Duration(milliseconds: 2700)); // build -> done
    await tester.pump(const Duration(milliseconds: 1600)); // auto-handoff
    await tester.pumpAndSettle();

    expect(find.byType(MainAppShell), findsOneWidget);

    // go to the Trends tab and scroll it
    container.read(mainAppProvider.notifier).goTab(MainScreen.trends);
    await tester.pumpAndSettle();
    expect(app().tab, MainScreen.trends);
    final scrollable = find.descendant(
        of: find.byType(TrendsScreen), matching: find.byType(Scrollable));
    await tester.drag(scrollable, const Offset(0, -260));
    await tester.pump();
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offset, greaterThan(80));

    // ---- rotate ----
    tester.view.physicalSize = const Size(920, 430);
    await tester.pumpAndSettle();
    expect(app().screen, MainScreen.trends, reason: 'tab kept across rotation');
    expect(app().tab, MainScreen.trends);
    expect(find.byType(TrendsScreen), findsOneWidget);

    tester.view.physicalSize = const Size(430, 920);
    await tester.pumpAndSettle();
    expect(app().tab, MainScreen.trends);
    // IndexedStack keeps the tab mounted -> scroll position preserved
    expect(tester.state<ScrollableState>(scrollable).position.pixels,
        moreOrLessEquals(offset, epsilon: 1),
        reason: 'Trends scroll offset survived rotation');
  });

  test('core providers are not autoDispose (state outlives listener removal)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    c.read(mainAppProvider.notifier).goTab(MainScreen.meds);
    c.read(onboardingFlowProvider.notifier).skipAuth();

    // a one-shot read adds then drops a listener; autoDispose would reset here
    c.read(mainAppProvider);
    c.read(onboardingFlowProvider);

    expect(c.read(mainAppProvider).tab, MainScreen.meds);
    expect(c.read(onboardingFlowProvider).oScreen, OnbScreen.steps);
  });
}
