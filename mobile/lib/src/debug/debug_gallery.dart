import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../features/analyzing/analyzing_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/meds/meds_screen.dart';
import '../features/nudge/nudge_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_sheet.dart';
import '../features/result/result_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/search/search_screen.dart';
import '../features/trends/trends_screen.dart';
import 'health_status_tile.dart';

/// name -> (label, builder, navTab). Each entry is a standalone static screen
/// previewable on its own at `/debug/{name}`. `navTab`, when set, adds the
/// bottom nav to the preview (the real nav lives in MainAppShell, not the
/// screens themselves).
typedef DebugEntry = ({String label, WidgetBuilder build, String? navTab});

/// The onboarding preview flips its own state machine only; keep it off the
/// real router gate ([onboardingCompleteProvider]).
void _onboardingPreviewNoop() {}

final debugScreens = <String, DebugEntry>{
  'onboarding': (
    label: 'Onboarding flow (sign-in → 6 steps → done)',
    build: (_) => const ProviderScope(
        child: OnboardingScreen(onComplete: _onboardingPreviewNoop)),
    navTab: null
  ),
  'home': (label: 'Home', build: (_) => const HomeScreen(), navTab: 'home'),
  'scan': (label: 'Scan', build: (_) => const ScanScreen(cameraEnabled: false), navTab: null),
  'analyzing': (label: 'Analyzing', build: (_) => const AnalyzingScreen(), navTab: null),
  'result': (label: 'Result — Avoid (noodles)', build: (_) => const ResultScreen(productId: 'noodles'), navTab: null),
  'result-caution': (label: 'Result — Caution (juice)', build: (_) => const ResultScreen(productId: 'juice'), navTab: null),
  'result-safe': (label: 'Result — Safe (chana)', build: (_) => const ResultScreen(productId: 'chana'), navTab: null),
  'trends': (label: 'Trends', build: (_) => const TrendsScreen(), navTab: 'trends'),
  'history': (label: 'History', build: (_) => const HistoryScreen(), navTab: 'history'),
  'meds': (label: 'Meds', build: (_) => const MedsScreen(), navTab: 'meds'),
  'search': (label: 'Search', build: (_) => const SearchScreen(), navTab: null),
  'search-empty': (label: 'Search — no results', build: (_) => const SearchScreen(showEmpty: true), navTab: null),
  'nudge': (label: 'Nudge (proactive check-in)', build: (_) => const NudgeScreen(), navTab: null),
  'profile-sheet': (label: 'Profile bottom sheet', build: (_) => const ProfileSheetPreview(), navTab: null),
};

/// Index screen: a list of every previewable screen.
class DebugGalleryScreen extends StatelessWidget {
  const DebugGalleryScreen({super.key, this.onOpen});
  final void Function(String name)? onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Cc.paper,
      appBar: AppBar(
        backgroundColor: Cc.paper,
        elevation: 0,
        title: const Text('CareCart · screen gallery', style: CcText.h2),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Static screens, hardcoded demo fixtures. Each opens standalone; '
              'the real navigation flow is at /app.',
              style: CcText.bodySm.copyWith(color: Cc.muted)),
          const SizedBox(height: 4),
          const HealthStatusTile(),
          const Divider(height: 24),
          for (final e in debugScreens.entries)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: Cc.paperRaised,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0x12151510)),
              ),
              child: ListTile(
                title: Text(e.value.label, style: CcText.listTitle),
                subtitle: Text('/debug/${e.key}', style: CcText.mono),
                trailing: const Icon(Icons.chevron_right_rounded, color: Cc.muted),
                onTap: () => onOpen?.call(e.key),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hosts one previewed screen, letterboxed to a phone width on wide windows.
/// One Scaffold; the screen is a plain [CcScreen], so no Scaffold nesting.
class DebugScreenHost extends StatelessWidget {
  const DebugScreenHost({super.key, required this.name, this.onBack});
  final String name;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final entry = debugScreens[name];
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('unknown screen')),
        body: Center(child: Text('No debug screen named "$name"')),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF2E2C26),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  children: [
                    Expanded(child: Builder(builder: entry.build)),
                    if (entry.navTab != null) CcBottomNav(active: entry.navTab!),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Material(
                color: const Color(0xCC20241A),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onBack,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text('‹ gallery',
                        style: TextStyle(color: Cc.paper, fontSize: 12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
