import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics_api.dart';
import '../core/history_api.dart';
import '../core/nudges_api.dart';
import '../core/product_api.dart';
import '../core/text.dart';
import '../core/vault_api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../features/analyzing/analyzing_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/meds/meds_screen.dart';
import '../features/fit/fit_screen.dart';
import '../features/nudge/nudge_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/product/product_screen.dart';
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

/// Synthetic GET /nudges payload for the standalone Nudge preview.
final _demoNudges = NudgesLoaded(NudgesPage(
  latestSeq: 1,
  items: [
    Nudge(
      id: 'demo',
      seq: 1,
      factor: 'sodium',
      hitCount: 4,
      windowDays: 14,
      createdAt: DateTime(2026, 8, 20),
      message:
          'Sodium was flagged in 4 of your last 14 days of scans. Next shop: '
          'pick a low-sodium namkeen or unsalted roasted nuts, rinse canned '
          'pulses before cooking, and leave out the seasoning sachet in '
          'instant noodles.',
    ),
  ],
));

/// Synthetic /analytics/trends payload for the standalone Trends preview.
final _demoTrends = TrendsLoaded(Trends(
  timezone: 'Asia/Kolkata',
  totalScans: 46,
  dietHealthScore: 68,
  deltaSevenDay: 4,
  trend: 'improving',
  weekly: [
    for (var i = 0; i < 6; i++)
      TrendBucket(
        periodStart: DateTime(2026, 7, 6 + i * 7),
        label: '${6 + i * 7} Jul',
        scans: 6 + i,
        avgScore: 54 + i * 3.0,
        medianScore: 55 + i * 3.0,
        minScore: 38 + i * 2,
        maxScore: 82 + i,
        safe: 2 + i,
        caution: 3,
        avoid: (i < 2) ? 2 : 1,
        dietHealthScore: 56 + i * 2,
      ),
  ],
  monthly: const [],
));

/// Synthetic GET /history payload for the standalone History preview.
final _demoHistory = HistoryLoaded(HistoryPage(
  total: 3,
  limit: 50,
  offset: 0,
  hasMore: false,
  items: [
    ScanHistoryEntry(
      id: '3',
      productName: 'Sea-Salt Crackers',
      score: 52,
      tier: 'caution',
      scannedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      keyReasons: const [
        HistoryReason(
            kind: 'condition_ceiling',
            severity: 'high',
            title: 'Sodium over your per-serving ceiling',
            factor: 'sodium'),
      ],
    ),
    ScanHistoryEntry(
      id: '2',
      productName: 'Cashew Energy Bar',
      score: 0,
      tier: 'avoid',
      hardStop: true,
      scannedAt: DateTime.now().toUtc().subtract(const Duration(hours: 5)),
      keyReasons: const [
        HistoryReason(
            kind: 'allergen',
            severity: 'high',
            title: 'Contains tree nuts — you told us you are allergic',
            factor: 'nut_allergen'),
      ],
    ),
    ScanHistoryEntry(
      id: '1',
      productName: 'Rolled Oats',
      score: 96,
      tier: 'safe',
      scannedAt: DateTime.now().toUtc().subtract(const Duration(days: 1, hours: 1)),
    ),
  ],
));

/// Synthetic GET /me/medications payload for the standalone Meds preview.
final _demoMeds = MedicationsLoaded(const [
  Medication(id: '1', name: 'Telmisartan', dosage: '40 mg'),
  Medication(id: '2', name: 'Metformin', dosage: '500 mg'),
  Medication(id: '3', name: 'Warfarin', dosage: '5 mg'),
]);

/// A stand-in Open Food Facts result for the standalone Product-facts preview.
const _demoScannedProduct = ScannedProduct(
  barcode: '8901058000108',
  name: 'Poha (Flattened Rice)',
  brand: 'Local Mills',
  ingredients: ['Flattened rice (poha)'],
  ingredientsText: 'Flattened rice (poha)',
  nutriments: {
    'energy_kcal_100g': 346,
    'carbohydrates_g_100g': 77.3,
    'sugars_g_100g': 0.9,
    'protein_g_100g': 6.6,
    'fat_g_100g': 1.2,
    'fiber_g_100g': 2.4,
    'sodium_mg_100g': 6,
  },
  servingSize: '40 g',
  cached: true,
);

final debugScreens = <String, DebugEntry>{
  'onboarding': (
    label: 'Onboarding flow (sign-in → 6 steps → done)',
    build: (_) => const ProviderScope(
        child: OnboardingScreen(onComplete: _onboardingPreviewNoop)),
    navTab: null
  ),
  'home': (label: 'Home', build: (_) => const HomeScreen(), navTab: 'home'),
  'scan': (label: 'Scan', build: (_) => const ScanScreen(cameraEnabled: false), navTab: null),
  'product': (
    label: 'Product facts (real barcode scan)',
    build: (_) => const ProductScreen(product: _demoScannedProduct),
    navTab: null
  ),
  'analyzing': (label: 'Analyzing', build: (_) => const AnalyzingScreen(), navTab: null),
  'result': (label: 'Result — Avoid (noodles)', build: (_) => const ResultScreen(productId: 'noodles'), navTab: null),
  'result-caution': (label: 'Result — Caution (juice)', build: (_) => const ResultScreen(productId: 'juice'), navTab: null),
  'result-safe': (label: 'Result — Safe (chana)', build: (_) => const ResultScreen(productId: 'chana'), navTab: null),
  'trends': (
    label: 'Trends',
    build: (_) => ProviderScope(
        overrides: [trendsProvider.overrideWith((ref) async => _demoTrends)],
        child: const TrendsScreen()),
    navTab: 'trends'
  ),
  'history': (
    label: 'History',
    build: (_) => ProviderScope(
        overrides: [historyPageProvider.overrideWith((ref) async => _demoHistory)],
        child: const HistoryScreen()),
    navTab: 'history'
  ),
  'meds': (
    label: 'Meds',
    build: (_) => ProviderScope(
        overrides: [medicationsProvider.overrideWith((ref) async => _demoMeds)],
        child: const MedsScreen()),
    navTab: 'meds'
  ),
  'search': (label: 'Search', build: (_) => const SearchScreen(), navTab: null),
  'search-empty': (label: 'Search — no results', build: (_) => const SearchScreen(showEmpty: true), navTab: null),
  'nudge': (
    label: 'Nudge (proactive check-in)',
    build: (_) => ProviderScope(
        overrides: [nudgesProvider.overrideWith((ref) async => _demoNudges)],
        child: const NudgeScreen()),
    navTab: null
  ),
  'profile-sheet': (label: 'Profile bottom sheet', build: (_) => const ProfileSheetPreview(), navTab: null),
  'fit': (label: 'CareCart Fit', build: (_) => const FitScreen(), navTab: null),
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
