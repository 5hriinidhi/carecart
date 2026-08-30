// The main-app state machine (mirrors the prototype's unprefixed `state` keys).
// Verifies screen navigation, the scan flow, and per-screen keys - and that it
// never touches the onboarding machine.

import 'package:carecart/src/routing/app_router.dart';
import 'package:carecart/src/state/main_app_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer c;
  MainApp app() => c.read(mainAppProvider.notifier);
  MainAppState st() => c.read(mainAppProvider);

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('defaults mirror the prototype', () {
    final s = st();
    expect(s.screen, MainScreen.home);
    expect(s.tab, MainScreen.home);
    expect(s.range, '7d');
    expect(s.filter, 'All');
    expect(s.query, '');
    expect(s.showNudge, isTrue);
    expect(s.showProfiles, isFalse);
    expect(s.profile, '');
    expect(s.showNav, isTrue);
  });

  test('goTab sets both screen and tab; nav hidden off the tab screens', () {
    app().goTab(MainScreen.trends);
    expect(st().screen, MainScreen.trends);
    expect(st().tab, MainScreen.trends);
    expect(st().showNav, isTrue);

    app().goScan();
    expect(st().screen, MainScreen.scan);
    expect(st().tab, MainScreen.trends, reason: 'tab is remembered');
    expect(st().showNav, isFalse);
  });

  test('back returns to the current tab screen', () {
    app().goTab(MainScreen.meds);
    app().goSearch();
    expect(st().screen, MainScreen.search);
    app().back();
    expect(st().screen, MainScreen.meds);
  });

  test('openResult sets pid and clears logged', () {
    app().logCurrentScan();
    app().openResult('juice');
    expect(st().screen, MainScreen.result);
    expect(st().pid, 'juice');
    expect(st().logged, isFalse);
  });

  test('startScan runs analyzing -> steps -> result', () async {
    await app().startScan('noodles');
    expect(st().screen, MainScreen.result);
    expect(st().pid, 'noodles');
    expect(st().step, 3);
  });

  test('startScan aborts if the user navigates away mid-scan', () async {
    final f = app().startScan('chana');
    app().goHome(); // bail out
    await f;
    expect(st().screen, MainScreen.home);
  });

  test('profile sheet + selection', () {
    app().openProfiles();
    expect(st().showProfiles, isTrue);
    app().selectProfile('Sunita');
    expect(st().profile, 'Sunita');
    expect(st().showProfiles, isFalse);
  });

  test('per-screen keys: range / filter / query / nudge / meds', () {
    app().setRange('30d');
    app().setFilter('Avoid');
    app().setQuery('noodles');
    app().dismissNudge();
    app().toggleMed('Telmisartan');
    final s = st();
    expect(s.range, '30d');
    expect(s.filter, 'Avoid');
    expect(s.query, 'noodles');
    expect(s.showNudge, isFalse);
    expect(s.medEnabled('Telmisartan'), isFalse);
    expect(s.medEnabled('Metformin'), isTrue);
  });

  test('is fully independent of the onboarding machine', () {
    // touching main-app state must not flip onboarding, and vice-versa
    app().goTab(MainScreen.history);
    expect(c.read(onboardingCompleteProvider), isFalse);

    c.read(onboardingCompleteProvider.notifier).markDone();
    expect(c.read(onboardingCompleteProvider), isTrue);
    expect(st().screen, MainScreen.history, reason: 'main-app state untouched');
  });
}
