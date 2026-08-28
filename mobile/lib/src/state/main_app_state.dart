import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/product_api.dart';

/// The 9 main-app screens, mirroring the prototype's `state.screen` string
/// values in `CareCart App.dc.html` ('home', 'scan', 'analyzing', ...).
enum MainScreen { home, scan, analyzing, result, trends, history, meds, search, nudge }

/// Barcode lookup progress on the scan screen (Phase 4.1).
enum LookupPhase { idle, looking, found, notFound, error }

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
    this.barcode,
    this.product,
    this.lookup = LookupPhase.idle,
    this.lookupError,
    this.ocrFallback = false,
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

  // ---- barcode scan (Phase 4.1) ----
  final String? barcode; // the barcode currently being looked up / last scanned
  final ScannedProduct? product; // resolved product on a successful lookup
  final LookupPhase lookup;
  final String? lookupError; // human message when lookup == error
  final bool ocrFallback; // backend said "not found, scan the ingredients"

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
    Object? barcode = _sentinel,
    Object? product = _sentinel,
    LookupPhase? lookup,
    Object? lookupError = _sentinel,
    bool? ocrFallback,
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
      barcode: identical(barcode, _sentinel) ? this.barcode : barcode as String?,
      product:
          identical(product, _sentinel) ? this.product : product as ScannedProduct?,
      lookup: lookup ?? this.lookup,
      lookupError: identical(lookupError, _sentinel)
          ? this.lookupError
          : lookupError as String?,
      ocrFallback: ocrFallback ?? this.ocrFallback,
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
  void goScan() => state = state.copyWith(
      screen: MainScreen.scan, lookup: LookupPhase.idle, ocrFallback: false);
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

  // ---- barcode scan (Phase 4.1) ----
  /// Look a scanned barcode up via `GET /products/{barcode}`.
  ///   found    -> state.product is set, lookup == found
  ///   notFound -> ocrFallback == true (client should offer OCR)
  ///   error    -> lookupError has a message
  Future<void> lookupBarcode(String rawBarcode) async {
    final code = rawBarcode.trim();
    if (code.isEmpty) return;

    state = state.copyWith(
      screen: MainScreen.scan,
      barcode: code,
      lookup: LookupPhase.looking,
      ocrFallback: false,
      lookupError: null,
      product: null,
    );

    final lookup = ref.read(productLookupProvider);
    ProductLookup result;
    try {
      result = await lookup(code);
    } catch (_) {
      result = const ProductLookupError('Product lookup failed.');
    }

    if (state.barcode != code) return; // a newer scan superseded this one

    switch (result) {
      case ProductFound(:final product):
        state = state.copyWith(lookup: LookupPhase.found, product: product);
      case ProductNotFound(:final fallbackToOcr):
        state = state.copyWith(
            lookup: LookupPhase.notFound, ocrFallback: fallbackToOcr);
      case ProductLookupError(:final message):
        state = state.copyWith(lookup: LookupPhase.error, lookupError: message);
    }
  }

  void dismissLookup() => state = state.copyWith(
      lookup: LookupPhase.idle, ocrFallback: false, lookupError: null);

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
