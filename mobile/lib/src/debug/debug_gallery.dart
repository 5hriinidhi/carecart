import 'package:flutter/material.dart';

import '../core/text.dart';
import '../core/theme.dart';
import '../features/analyzing/analyzing_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/meds/meds_screen.dart';
import '../features/nudge/nudge_screen.dart';
import '../features/profile/profile_sheet.dart';
import '../features/result/result_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/search/search_screen.dart';
import '../features/trends/trends_screen.dart';
import 'health_status_tile.dart';

/// name -> (label, builder). Each entry is a standalone static screen that can
/// be previewed on its own at `/debug/{name}`, no navigation flow required.
final debugScreens = <String, ({String label, WidgetBuilder build})>{
  'home': (label: 'Home', build: (_) => const HomeScreen()),
  'scan': (label: 'Scan', build: (_) => const ScanScreen()),
  'analyzing': (label: 'Analyzing', build: (_) => const AnalyzingScreen()),
  'result': (label: 'Result — Avoid (noodles)', build: (_) => const ResultScreen(productId: 'noodles')),
  'result-caution': (label: 'Result — Caution (juice)', build: (_) => const ResultScreen(productId: 'juice')),
  'result-safe': (label: 'Result — Safe (chana)', build: (_) => const ResultScreen(productId: 'chana')),
  'trends': (label: 'Trends', build: (_) => const TrendsScreen()),
  'history': (label: 'History', build: (_) => const HistoryScreen()),
  'meds': (label: 'Meds', build: (_) => const MedsScreen()),
  'search': (label: 'Search', build: (_) => const SearchScreen()),
  'search-empty': (label: 'Search — no results', build: (_) => const SearchScreen(showEmpty: true)),
  'nudge': (label: 'Nudge (proactive check-in)', build: (_) => const NudgeScreen()),
  'profile-sheet': (label: 'Profile bottom sheet', build: (_) => const ProfileSheetPreview()),
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
          Text('Phase 2.2 — static screens, hardcoded demo fixtures. '
              'Each opens standalone; no auth / nav flow wired up yet.',
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

/// Hosts one previewed screen inside a phone-width frame (so wide web/desktop
/// windows still show it at a realistic size).
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E2C26),
        foregroundColor: Cc.paper,
        elevation: 0,
        title: Text(entry.label, style: const TextStyle(fontSize: 15, color: Cc.paper)),
        leading: BackButton(onPressed: onBack),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 430,
              height: 908,
              child: MediaQuery(
                // pretend we're on a 430x908 phone regardless of window size
                data: MediaQuery.of(context).copyWith(
                  size: const Size(430, 908),
                  padding: const EdgeInsets.only(top: 24, bottom: 12),
                ),
                child: Builder(builder: entry.build),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
