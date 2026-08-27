import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../state/main_app_state.dart';
import 'analyzing/analyzing_screen.dart';
import 'history/history_screen.dart';
import 'home/home_screen.dart';
import 'meds/meds_screen.dart';
import 'nudge/nudge_screen.dart';
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
        case 'scan':
          app.goScan();
      }
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
            HomeScreen(onNav: nav, onScan: app.goScan, onOpenProfiles: app.openProfiles),
            TrendsScreen(range: s.range, onNav: nav, onScan: app.goScan),
            HistoryScreen(onNav: nav, onScan: app.goScan),
            MedsScreen(onNav: nav, onScan: app.goScan),
          ],
        );
      case MainScreen.scan:
        bg = const Color(0xFF14170F);
        body = ScanScreen(onBack: app.back, onPick: app.startScan);
      case MainScreen.analyzing:
        bg = Cc.paper;
        body = AnalyzingScreen(activeStep: s.step);
      case MainScreen.result:
        bg = Cc.paper;
        body = ResultScreen(
          productId: s.pid ?? 'noodles',
          onHome: app.goHome,
          onScan: app.goScan,
        );
      case MainScreen.search:
        bg = Cc.paper;
        body = SearchScreen(onBack: app.back);
      case MainScreen.nudge:
        bg = const Color(0xFFF7E2D5);
        body = NudgeScreen(onHome: app.goHome);
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: bg,
          body: body,
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
          ),
      ],
    );
  }
}
