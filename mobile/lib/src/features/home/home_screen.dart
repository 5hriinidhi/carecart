import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics_api.dart';
import '../../core/build_config.dart';
import '../../core/history_api.dart';
import '../../core/me_api.dart';
import '../../core/nudges_api.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/vault_api.dart';
import '../../core/widgets.dart';

const _kWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// Home — turn `1a` / `state.screen == 'home'`. Wired to /me, /analytics/trends,
/// /nudges and /history — everything below the greeting is the user's own data
/// (or an empty state), never a fixture.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.onNav, this.onScan, this.onOpenProfiles});
  final void Function(String route)? onNav;
  final VoidCallback? onScan;
  final VoidCallback? onOpenProfiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The signed-in user's name drives the greeting + avatar; until it loads (or
    // if it never set) we fall back to the generic copy.
    final me = ref.watch(meProvider).asData?.value ?? const MeInfo();
    final firstName = me.firstName;
    final initial = me.initial;

    // Diet Health Score — real, starts at 0 and averages up as scans come in.
    final trends = ref.watch(trendsProvider).asData?.value;
    final t = trends is TrendsLoaded ? trends.trends : null;
    final hasTrend = t != null && !t.isEmpty;
    final dhs = hasTrend ? t.dietHealthScore : 0;
    final dhsDelta = hasTrend ? t.deltaSevenDay : 0;
    final dhsSub = !hasTrend
        ? 'Starts at 0 and averages up as you scan. Scan a label to begin.'
        : '${dhsDelta > 0 ? 'Up $dhsDelta' : dhsDelta < 0 ? 'Down ${-dhsDelta}' : 'Steady'} '
            'over the last 7 days · ${t.trend}.';

    // Proactive nudge — only when the engine has actually produced one.
    final nudges = ref.watch(nudgesProvider).asData?.value;
    final nudge = (nudges is NudgesLoaded && nudges.page.items.isNotEmpty)
        ? nudges.page.items.first
        : null;

    // Recent scans for the "Today" list.
    final history = ref.watch(historyPageProvider).asData?.value;
    final recent = switch (history) {
      HistoryLoaded(:final page) => page.items.take(4).toList(),
      HistoryOffline(:final items) => items.take(4).toList(),
      _ => const <ScanHistoryEntry>[],
    };

    final now = DateTime.now();
    final todayLabel =
        '${_kWeekdays[now.weekday - 1]}, ${now.day} ${_kMonths[now.month - 1]}';
    return CcScreen(
      background: Cc.paper,
      child: ListView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          children: [
            // header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(todayLabel.toUpperCase(),
                            style: CcText.label
                                .copyWith(fontSize: 12, letterSpacing: 0.96)),
                        if (kDemoMode) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                                color: Cc.accent.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text('DEMO DATA',
                                style: CcText.label.copyWith(
                                    fontSize: 9,
                                    letterSpacing: 0.8,
                                    color: Cc.oliveDark)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 5),
                      Text('Good evening, $firstName', style: CcText.h1),
                    ],
                  ),
                ),
                GestureDetector(
                  key: const Key('home-profile-button'),
                  onTap: onOpenProfiles,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Cc.olive, shape: BoxShape.circle),
                    child: Text(initial,
                        style: const TextStyle(
                            fontFamily: 'Bricolage',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Cc.paper)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // diet health score
            GestureDetector(
              onTap: () => onNav?.call('trends'),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Cc.sage, borderRadius: BorderRadius.circular(26)),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: CustomPaint(
                        painter: _RingPainter(dhs / 100),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$dhs',
                                  style: const TextStyle(
                                      fontFamily: 'Bricolage',
                                      fontSize: 30,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                      color: Cc.inkSoft)),
                              Text('/100',
                                  style: CcText.mono.copyWith(
                                      fontSize: 9, color: Cc.oliveDark, letterSpacing: 0.6)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Diet Health Score',
                              style: TextStyle(
                                  fontFamily: 'Bricolage',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Cc.inkSoft)),
                          const SizedBox(height: 5),
                          Text(dhsSub,
                              style: CcText.body
                                  .copyWith(color: Cc.oliveDark, fontSize: 12.5)),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(999)),
                            child: Text('See the trend →',
                                style: CcText.bodySm.copyWith(
                                    color: Cc.oliveDark, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // CareCart Fit — lifestyle + medicines correlation
            GestureDetector(
              onTap: () => onNav?.call('fit'),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
                decoration: BoxDecoration(
                    color: Cc.sageSoft, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    const Icon(Icons.insights_rounded,
                        size: 22, color: Cc.oliveDark),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CareCart Fit',
                              style: TextStyle(
                                  fontFamily: 'Bricolage',
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: Cc.ink)),
                          const SizedBox(height: 2),
                          Text('How your lifestyle + meds line up',
                              style: CcText.bodySm
                                  .copyWith(color: Cc.oliveDark, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Cc.oliveDark),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // proactive nudge — only once the engine has produced one
            if (nudge != null) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7E2D5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x59D07E52)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Cc.accentDeep, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('A pattern worth a look',
                              style: TextStyle(
                                  fontFamily: 'Bricolage',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF8A4526))),
                          const SizedBox(height: 4),
                          Text(nudge.message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: CcText.body
                                  .copyWith(color: const Color(0xFF7A4A31))),
                          const SizedBox(height: 11),
                          GestureDetector(
                            onTap: () => onNav?.call('nudge'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 8),
                              decoration: BoxDecoration(
                                  color: Cc.accentDeep,
                                  borderRadius: BorderRadius.circular(999)),
                              child: const Text("What's driving it",
                                  style: TextStyle(
                                      fontFamily: 'DMSans',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // action tiles
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ActionTile(
                    dark: true,
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Scan a label',
                    sub: 'Verdict in ~2 seconds',
                    onTap: onScan,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionTile(
                    dark: false,
                    icon: Icons.search_rounded,
                    title: 'Look it up',
                    sub: 'No barcode needed',
                    onTap: () => onNav?.call('search'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            CcSectionHead('Recent scans',
                trailing: 'All history →', onTrailing: () => onNav?.call('history')),
            const SizedBox(height: 10),
            if (recent.isEmpty)
              Text('Nothing scanned yet — your recent scans show up here.',
                  style: CcText.bodySm.copyWith(color: Cc.muted))
            else
              for (final e in recent) ...[
                _ScanRow(
                  name: e.productName,
                  note: e.tier[0].toUpperCase() + e.tier.substring(1),
                  score: e.score,
                  when: _hhmm(e.scannedAt),
                ),
                const SizedBox(height: 9),
              ],

            const SizedBox(height: 7),
            _MedsCard(onOpen: () => onNav?.call('meds')),
          ],
        ),
    );
  }
}

class _MedsCard extends ConsumerWidget {
  const _MedsCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(medicationsProvider);
    final meds = switch (async.asData?.value) {
      MedicationsLoaded(:final items) => items,
      _ => const <Medication>[],
    };
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        decoration: BoxDecoration(
            color: const Color(0xFFEAEADB),
            borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      meds.isEmpty
                          ? 'No medications on file'
                          : 'Watching ${meds.length} medication${meds.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontFamily: 'Bricolage',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Cc.ink)),
                ),
                Text(meds.isEmpty ? 'Add →' : 'Manage →',
                    style: CcText.bodySm
                        .copyWith(color: Cc.olive, fontWeight: FontWeight.w500)),
              ],
            ),
            if (meds.isNotEmpty) ...[
              const SizedBox(height: 11),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final m in meds)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: Cc.paperRaised,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0x14151510)),
                      ),
                      child: Text(m.name,
                          style: CcText.bodySm.copyWith(color: Cc.oliveDark)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(
      {required this.dark,
      required this.icon,
      required this.title,
      required this.sub,
      this.onTap});
  final bool dark;
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? Cc.inkSoft : Cc.paperRaised,
          borderRadius: BorderRadius.circular(20),
          border: dark ? null : Border.all(color: const Color(0x17151510)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: dark ? Cc.sage : Cc.olive),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontFamily: 'Bricolage',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: dark ? Cc.paper : Cc.ink)),
            const SizedBox(height: 3),
            Text(sub,
                style: CcText.bodySm
                    .copyWith(color: dark ? Colors.white.withValues(alpha: 0.7) : Cc.muted)),
          ],
        ),
      ),
    );
  }
}

String _hhmm(DateTime dt) {
  final l = dt.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

class _ScanRow extends StatelessWidget {
  const _ScanRow(
      {required this.name,
      required this.note,
      required this.score,
      required this.when});
  final String name;
  final String note;
  final int score;
  final String when;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x12151510)),
      ),
      child: Row(
        children: [
          CcScoreChip(score),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CcText.listTitle),
                const SizedBox(height: 2),
                Text(note, style: CcText.bodySm.copyWith(color: Cc.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(when, style: CcText.mono.copyWith(color: const Color(0xFFA3A491))),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4.5;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = const Color(0x26202419);
    final prog = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = Cc.oliveDark;
    canvas.drawCircle(c, r, track);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
        2 * math.pi * fraction, false, prog);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction;
}
