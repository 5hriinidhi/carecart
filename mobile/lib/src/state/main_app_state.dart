import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../core/notifications.dart';
import '../core/product_api.dart';
import 'verdict_events.dart';

/// The 9 main-app screens, mirroring the prototype's `state.screen` string
/// values in `CareCart App.dc.html` ('home', 'scan', 'analyzing', ...).
enum MainScreen {
  home,
  scan,
  analyzing,
  result,
  product, // real barcode scan -> product facts (no personal verdict yet)
  trends,
  history,
  meds,
  search,
  nudge,
  fit, // lifestyle + medicines correlation (CareCart Fit)
  profile // full editable profile page
}

/// Barcode lookup progress on the scan screen (Phase 4.1).
enum LookupPhase { idle, looking, found, notFound, error }

/// Full scan → verdict pipeline progress (Phase 4.4): look the barcode up,
/// then score it against the signed-in user's vault.
enum VerdictPhase { idle, looking, scoring, done, error }

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
    this.profile = '',
    this.logged = false,
    this.accepted = false,
    this.medOff = const {},
    this.barcode,
    this.product,
    this.lookup = LookupPhase.idle,
    this.lookupError,
    this.ocrFallback = false,
    this.verdictPhase = VerdictPhase.idle,
    this.verdict,
    this.verdictError,
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
  final String profile; // demo family-switcher: picked persona's first name ('' = self)
  final bool logged; // result -> "saved to history"
  final bool accepted; // nudge -> "reminder set"
  final Map<String, bool> medOff; // med name -> toggled off?

  // ---- barcode scan (Phase 4.1) ----
  final String? barcode; // the barcode currently being looked up / last scanned
  final ScannedProduct? product; // resolved product on a successful lookup
  final LookupPhase lookup;
  final String? lookupError; // human message when lookup == error
  final bool ocrFallback; // backend said "not found, scan the ingredients"

  // ---- scan → verdict pipeline (Phase 4.4) ----
  final VerdictPhase verdictPhase;
  final ScanVerdict? verdict; // the live verdict shown on the result screen
  final String? verdictError;

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
    VerdictPhase? verdictPhase,
    Object? verdict = _sentinel,
    Object? verdictError = _sentinel,
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
      verdictPhase: verdictPhase ?? this.verdictPhase,
      verdict: identical(verdict, _sentinel) ? this.verdict : verdict as ScanVerdict?,
      verdictError: identical(verdictError, _sentinel)
          ? this.verdictError
          : verdictError as String?,
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
        screen: MainScreen.scan,
        lookup: LookupPhase.idle,
        ocrFallback: false,
        verdictPhase: VerdictPhase.idle,
        verdict: null,
        verdictError: null,
      );
  void goSearch() => state = state.copyWith(screen: MainScreen.search);
  void goNudge() => state = state.copyWith(screen: MainScreen.nudge);
  void goFit() => state = state.copyWith(screen: MainScreen.fit);
  void goProfile() => state = state.copyWith(screen: MainScreen.profile);

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

  // ---- barcode scan ----
  void dismissLookup() => state = state.copyWith(
      lookup: LookupPhase.idle, ocrFallback: false, lookupError: null);

  /// What a real barcode scan does today: look the code up via
  /// `GET /products/{barcode}` and — if it's in the database — show the product's
  /// facts (name, brand, nutrition per 100 g, ingredients).
  ///
  /// It deliberately stops there. The personalised "how good is this for you"
  /// verdict ([scanBarcode]) is gated on the medicines + lifestyle correlation
  /// score and stays dormant until that lands. A miss keeps the user on the scan
  /// screen with a clear "not in the database" banner — never a wrong product.
  Future<void> scanProduct(String rawBarcode) async {
    final code = rawBarcode.trim();
    if (code.isEmpty) return;

    state = state.copyWith(
      screen: MainScreen.scan,
      barcode: code,
      lookup: LookupPhase.looking,
      ocrFallback: false,
      lookupError: null,
      product: null,
      // keep the verdict machine idle — we are not scoring in this build
      verdictPhase: VerdictPhase.idle,
      verdict: null,
      verdictError: null,
    );

    ProductLookup result;
    try {
      result = await ref.read(productLookupProvider)(code);
    } catch (_) {
      result = const ProductLookupError('Product lookup failed.');
    }

    if (state.barcode != code) return; // a newer scan superseded this one

    switch (result) {
      case ProductFound(:final product):
        state = state.copyWith(
          screen: MainScreen.product,
          lookup: LookupPhase.found,
          product: product,
        );
      case ProductNotFound(:final fallbackToOcr):
        state = state.copyWith(
            lookup: LookupPhase.notFound, ocrFallback: fallbackToOcr);
      case ProductLookupError(:final message):
        state = state.copyWith(lookup: LookupPhase.error, lookupError: message);
    }
  }

  /// The full scan → verdict pipeline:
  ///   look it up (`GET /products/{barcode}`) → if found, score it against the
  ///   signed-in user's vault (`POST /scan/verdict`) → land on the result screen.
  ///
  /// NOT wired to the UI in this build — [scanProduct] (lookup only) is what a
  /// scan runs today. This comes back on when the medicines + lifestyle
  /// correlation score lands and the result screen shows a personal verdict.
  ///
  /// A "not found" still ends on the scan screen with [ocrFallback] set; a
  /// failure at either step leaves [verdictPhase] == error with a message.
  Future<void> scanBarcode(String rawBarcode) async {
    final code = rawBarcode.trim();
    if (code.isEmpty) return;

    state = state.copyWith(
      screen: MainScreen.scan,
      barcode: code,
      lookup: LookupPhase.looking,
      ocrFallback: false,
      lookupError: null,
      product: null,
      verdictPhase: VerdictPhase.looking,
      verdict: null,
      verdictError: null,
    );

    // ---- step 1: barcode → product ----
    ProductLookup lookupResult;
    try {
      lookupResult = await ref.read(productLookupProvider)(code);
    } catch (_) {
      lookupResult = const ProductLookupError('Product lookup failed.');
    }
    if (state.barcode != code) return; // superseded by a newer scan

    switch (lookupResult) {
      case ProductNotFound(:final fallbackToOcr):
        state = state.copyWith(
          lookup: LookupPhase.notFound,
          ocrFallback: fallbackToOcr,
          verdictPhase: VerdictPhase.idle,
        );
        return;
      case ProductLookupError(:final message):
        state = state.copyWith(
          lookup: LookupPhase.error,
          lookupError: message,
          verdictPhase: VerdictPhase.error,
          verdictError: message,
        );
        return;
      case ProductFound(:final product):
        state = state.copyWith(
          lookup: LookupPhase.found,
          product: product,
          verdictPhase: VerdictPhase.scoring,
        );
    }

    // ---- step 2: product → verdict ----
    final p = state.product!;
    ScanVerdictOutcome scored;
    try {
      scored = await ref.read(scanVerdictProvider)(
        ingredients: p.ingredients,
        nutriments: p.nutriments.map(
          (k, v) => MapEntry(k, (v is num) ? v : num.tryParse('$v') ?? 0),
        ),
        barcode: code,
        productName: p.displayName,
      );
    } catch (_) {
      scored = const ScanVerdictFailed("Couldn't score this product.");
    }
    if (state.barcode != code) return;

    switch (scored) {
      case ScanVerdictReady(:final verdict):
        state = state.copyWith(
          screen: MainScreen.result,
          verdict: verdict,
          verdictPhase: VerdictPhase.done,
        );
        // Phase 5 diet-logging hooks in here: every successful verdict is an
        // event on verdictEventProvider.
        ref.read(verdictEventProvider.notifier).emit(VerdictEvent(
              barcode: code,
              productName: p.displayName,
              product: p,
              verdict: verdict,
              at: DateTime.now(),
            ));
        // Phase 5.3: if this scan crossed a pattern threshold, fire a local
        // notification. The service no-ops unless the user has already granted
        // permission (asked explicitly on the nudge screen) — never assumed.
        final nudge = verdict.nudge;
        if (nudge != null) {
          unawaited(ref.read(notificationServiceProvider).showNudge(
                title: 'A pattern worth a look',
                body: nudge.message,
              ));
        }
      case ScanVerdictFailed(:final message):
        state = state.copyWith(
          lookup: LookupPhase.error,
          lookupError: message,
          verdictPhase: VerdictPhase.error,
          verdictError: message,
        );
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
