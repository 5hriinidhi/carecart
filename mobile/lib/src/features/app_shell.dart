import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics_api.dart';
import '../core/auth_repository.dart';
import '../core/build_config.dart';
import '../core/connectivity.dart';
import '../core/history_api.dart';
import '../core/local_cache.dart';
import '../core/nudges_api.dart';
import '../core/theme.dart';
import '../core/vault_api.dart';
import '../core/widgets.dart';
import '../routing/app_router.dart';
import '../state/main_app_state.dart';
import '../state/onboarding_state.dart';
import 'analyzing/analyzing_screen.dart';
import 'history/history_screen.dart';
import 'home/home_screen.dart';
import 'meds/meds_screen.dart';
import 'fit/fit_screen.dart';
import 'nudge/nudge_screen.dart';
import 'product/product_screen.dart';
import 'profile/profile_page.dart';
import 'profile/profile_sheet.dart';
import 'result/result_screen.dart';
import 'scan/scan_screen.dart';
import 'search/search_screen.dart';
import 'trends/trends_screen.dart';

/// The single main-app route. Owns the ONE Scaffold, the persistent bottom nav
/// + centre scan FAB, and swaps its body based on `mainAppProvider.screen`.
///
/// The four tab screens live in an IndexedStack so they stay mounted (scroll
/// position, etc. persist); scan / analyzing / result / search / nudge take
/// over the whole body with no nav, exactly like the prototype.
class MainAppShell extends ConsumerWidget {
  const MainAppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mainAppProvider);
    final app = ref.read(mainAppProvider.notifier);

    // route strings coming from screen callbacks -> notifier
    void nav(String key) {
      switch (key) {
        case 'home' || 'trends' || 'history' || 'meds':
          app.goTab(MainScreen.values.byName(key));
        case 'search':
          app.goSearch();
        case 'nudge':
          app.goNudge();
        case 'fit':
          app.goFit();
        case 'profile':
          app.goProfile();
        case 'scan':
          app.goScan();
      }
    }

    Future<void> deleteAccount() async {
      // best-effort server delete, then forget the session and reset the app
      await ref.read(vaultApiProvider).deleteAccount();
      await ref.read(authControllerProvider).signOut();
      await ref.read(localCacheProvider).clear(); // cached PHI must not linger
      ref.invalidate(historyPageProvider);
      ref.invalidate(trendsProvider);
      ref.invalidate(nudgesProvider);
      ref.invalidate(medicationsProvider);
      ref.invalidate(mainAppProvider);
      ref.invalidate(onboardingFlowProvider);
      ref.read(onboardingCompleteProvider.notifier).reset(); // -> router shows /onboarding
    }

    final tabIndex = kNavTabs.indexOf(s.tab).clamp(0, kNavTabs.length - 1);

    final Widget body;
    final Color bg;
    switch (s.screen) {
      case MainScreen.home ||
            MainScreen.trends ||
            MainScreen.history ||
            MainScreen.meds:
        bg = Cc.paper;
        body = IndexedStack(
          index: tabIndex,
          children: [
            HomeScreen(onNav: nav, onScan: app.goScan, onOpenProfiles: app.goProfile),
            TrendsScreen(range: s.range, onNav: nav, onScan: app.goScan),
            HistoryScreen(onNav: nav, onScan: app.goScan),
            MedsScreen(onNav: nav, onScan: app.goScan),
          ],
        );
      case MainScreen.scan:
        bg = const Color(0xFF14170F);
        body = Stack(
          children: [
            ScanScreen(
              onBack: app.back,
              onPick: app.startScan,
              onBarcode: app.scanProduct,
              showDemoPicker: ref.watch(debugGalleryEnabledProvider),
            ),
            if (s.lookup != LookupPhase.idle)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _LookupBanner(state: s, onDismiss: app.dismissLookup),
              ),
          ],
        );
      case MainScreen.analyzing:
        bg = Cc.paper;
        body = AnalyzingScreen(activeStep: s.step);
      case MainScreen.product:
        bg = Cc.paper;
        body = s.product == null
            ? const SizedBox.shrink()
            : ProductScreen(
                product: s.product!,
                onClose: app.goHome,
                onScanNext: app.goScan,
              );
      case MainScreen.result:
        bg = Cc.paper;
        body = ResultScreen(
          productId: s.pid ?? 'noodles',
          verdict: s.verdict, // live Phase 4.4 verdict; null -> demo fixture
          onHome: app.goHome,
          onScan: app.goScan,
        );
      case MainScreen.search:
        bg = Cc.paper;
        body = SearchScreen(onBack: app.back);
      case MainScreen.nudge:
        bg = const Color(0xFFF7E2D5);
        body = NudgeScreen(onHome: app.goHome);
      case MainScreen.fit:
        bg = Cc.paper;
        body = FitScreen(
          onClose: app.goHome,
          onEditLifestyle: app.goProfile,
        );
      case MainScreen.profile:
        bg = Cc.paper;
        body = ProfilePage(
          onClose: app.back,
          onOpenFit: app.goFit,
          onOpenMeds: () => app.goTab(MainScreen.meds),
          onDeleteAccount: deleteAccount,
        );
    }

    final offline = ref.watch(isOfflineProvider);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: bg,
          body: Column(
            children: [
              if (offline) const _OfflineStrip(),
              Expanded(child: body),
            ],
          ),
          bottomNavigationBar: s.showNav
              ? CcBottomNav(
                  active: s.tab.name,
                  onTapItem: nav,
                  onTapScan: app.goScan,
                )
              : null,
        ),
        if (s.showProfiles)
          ProfileSheetOverlay(
            onDismiss: app.closeProfiles,
            onPick: (p) => app.selectProfile(p.name.split(' ').first),
            onDeleteAccount: deleteAccount,
          ),
      ],
    );
  }
}

/// Persistent thin strip shown at the top of the app whenever the last network
/// call to the backend failed to connect (Phase 6.3). Screens that have a
/// local cache render it; the rest degrade to their normal error state.
class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF8A4526),
      child: SafeArea(
        bottom: false,
        child: Container(
          key: const Key('app-offline-strip'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 14),
          child: const Text(
            "Offline — showing saved data where we have it",
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: Cc.paper),
          ),
        ),
      ),
    );
  }
}

/// Bottom strip on the scan screen that reports barcode-lookup progress.
class _LookupBanner extends StatelessWidget {
  const _LookupBanner({required this.state, this.onDismiss});
  final MainAppState state;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final (String title, String? sub, Color accent) = switch (state.lookup) {
      LookupPhase.looking => ('Looking up ${state.barcode}…', null, Cc.sage),
      LookupPhase.found => (
          state.product?.displayName ?? 'Product found',
          (state.product?.fromLocalCache ?? false)
              ? 'Offline — saved copy from this device'
              : <String>[
                  ?state.product?.brand,
                  '${state.product?.ingredients.length ?? 0} ingredients',
                  if (state.product?.cached ?? false) 'cached',
                  if (state.product?.stale ?? false) 'offline copy',
                ].join(' · '),
          (state.product?.fromLocalCache ?? false) ? Cc.accent : Cc.sage,
        ),
      LookupPhase.notFound => (
          "Not in the database",
          state.ocrFallback
              ? 'Scan the ingredients list instead'
              : null,
          Cc.accent,
        ),
      LookupPhase.error => (
          'Lookup failed',
          state.lookupError,
          const Color(0xFFB44F35),
        ),
      LookupPhase.idle => ('', null, Cc.sage),
    };

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
        decoration: BoxDecoration(
          color: const Color(0xF2201F17),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            if (state.lookup == LookupPhase.looking)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Cc.sage),
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Cc.paper)),
                  if (sub != null && sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub,
                        style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 11.5,
                            color: Color(0x99F1F0E4))),
                  ],
                ],
              ),
            ),
            if (state.lookup != LookupPhase.looking)
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: Color(0x99F1F0E4)),
              ),
          ],
        ),
      ),
    );
  }
}
