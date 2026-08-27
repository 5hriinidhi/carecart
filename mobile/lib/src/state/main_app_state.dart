import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The 9 main-app screens, mirroring the prototype's `state.screen` string
/// values in `CareCart App.dc.html` ('home', 'scan', 'analyzing', ...).
enum MainScreen { home, scan, analyzing, result, trends, history, meds, search, nudge }

/// The four bottom-nav tabs (a subset of [MainScreen], like the prototype's
/// `state.tab`).
const kNavTabs = [MainScreen.home, MainScreen.trends, MainScreen.history, MainScreen.meds];

/// Immutable snapshot of the main-app state machine.
///
/// Field-for-field port of the prototype's UNPREFIXED `state` keys:
///   screen, tab, pid, step, range, filter, query, showNudge, showProfiles,
///   profile, logged, accepted, medOff
///
/// The onboarding keys (o*) are a SEPARATE machine - see
/// [onboardingCompleteProvider] in routing/app_router.dart. Do not merge them.
@immutable
class MainAppState {
  const MainAppState({
    this.screen = MainScreen.home,
    this.tab = MainScreen.home,
    this.pid,
    this.step = 0,
    this.range = '7d',
    this.filter = 'All',
    this.query = '',
    this.showNudge = true,
    this.showProfiles = false,
    this.profile = 'Aarav',
    this.logged = false,
    this.accepted = false,
    this.medOff = const {},
  });

  final MainScreen screen;
  final MainScreen tab; // last-visited nav tab
  final String? pid; // product being viewed on the result screen
  final int step; // analyze progress, 0..3
  final String range; // '7d' | '30d' | '90d'  (trends)
  final String filter; // 'All' | 'Safe' | 'Caution' | 'Avoid'  (history)
  final String query; // search box
  final bool showNudge; // home nudge card
  final bool showProfiles; // profile bottom sheet
  final String profile; // active profile first name
  final bool logged; // result -> "saved to history"
  final bool accepted; // nudge -> "reminder set"
  final Map<String, bool> medOff; // med name -> toggled off?

  /// Bottom nav is only shown on the four tab screens (prototype `showNav`).
  bool get showNav => kNavTabs.contains(screen);

  bool medEnabled(String name) => !(medOff[name] ?? false);

  MainAppState copyWith({
    MainScreen? screen,
    MainScreen? tab,
    Object? pid = _sentinel,
    int? step,
    String? range,
    String? filter,
    String? query,
    bool? showNudge,
    bool? showProfiles,
    String? profile,
    bool? logged,
    bool? accepted,
    Map<String, bool>? medOff,
  }) {
    return MainAppState(
      screen: screen ?? this.screen,
      tab: tab ?? this.tab,
      pid: identical(pid, _sentinel) ? this.pid : pid as String?,
      step: step ?? this.step,
      range: range ?? this.range,
      filter: filter ?? this.filter,
      query: query ?? this.query,
      showNudge: showNudge ?? this.showNudge,
      showProfiles: showProfiles ?? this.showProfiles,
      profile: profile ?? this.profile,
      logged: logged ?? this.logged,
      accepted: accepted ?? this.accepted,
      medOff: medOff ?? this.medOff,
    );
  }

  static const _sentinel = Object();
}

/// The main-app state machine. Modern-API equivalent of a Riverpod
/// StateNotifier; methods mirror the prototype's handlers (`go`, `goScan`,
/// `back`, `open`, `startScan`, ...).
class MainApp extends Notifier<MainAppState> {
  @override
  MainAppState build() => const MainAppState();

  // ---- navigation ----
  /// Prototype `go(screen, tab)` for the four nav tabs.
  void goTab(MainScreen tab) {
    assert(kNavTabs.contains(tab));
    state = state.copyWith(screen: tab, tab: tab);
  }

  void goHome() => state = state.copyWith(screen: MainScreen.home, tab: MainScreen.home);
  void goScan() => state = state.copyWith(screen: MainScreen.scan);
  void goSearch() => state = state.copyWith(screen: MainScreen.search);
  void goNudge() => state = state.copyWith(screen: MainScreen.nudge);

  /// Prototype `back`: return to the current tab's screen.
  void back() => state = state.copyWith(
      screen: state.tab == MainScreen.home ? MainScreen.home : state.tab);

  /// Prototype `open(pid)`: jump straight to a verdict.
  void openResult(String pid) =>
      state = state.copyWith(screen: MainScreen.result, pid: pid, logged: false);

  /// Prototype `startScan(pid)`: analyzing -> (steps) -> result.
  Future<void> startScan(String pid) async {
    state = state.copyWith(
        screen: MainScreen.analyzing, pid: pid, step: 0, logged: false);
    for (var i = 1; i <= 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (state.screen != MainScreen.analyzing) return; // user navigated away
      state = state.copyWith(step: i);
    }
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (state.screen == MainScreen.analyzing) {
      state = state.copyWith(screen: MainScreen.result);
    }
  }

  // ---- per-screen state ----
  void setRange(String r) => state = state.copyWith(range: r);
  void setFilter(String f) => state = state.copyWith(filter: f);
  void setQuery(String q) => state = state.copyWith(query: q);
  void dismissNudge() => state = state.copyWith(showNudge: false);
  void openProfiles() => state = state.copyWith(showProfiles: true);
  void closeProfiles() => state = state.copyWith(showProfiles: false);
  void selectProfile(String firstName) =>
      state = state.copyWith(profile: firstName, showProfiles: false);
  void logCurrentScan() => state = state.copyWith(logged: true);
  void acceptNudge() => state = state.copyWith(accepted: true);

  void toggleMed(String name) {
    final next = Map<String, bool>.from(state.medOff);
    next[name] = !(next[name] ?? false);
    state = state.copyWith(medOff: next);
  }
}

final mainAppProvider =
    NotifierProvider<MainApp, MainAppState>(MainApp.new);
