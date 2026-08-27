import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../fixtures/demo_data.dart';

/// Static home screen — turn `1a` / `state.screen == 'home'` in CareCart App.dc.html.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.onNav, this.onScan, this.onOpenProfiles});
  final void Function(String route)? onNav;
  final VoidCallback? onScan;
  final VoidCallback? onOpenProfiles;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Cc.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
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
                      Text(kTodayLabel.toUpperCase(),
                          style: CcText.label.copyWith(fontSize: 12, letterSpacing: 0.96)),
                      const SizedBox(height: 5),
                      const Text('Good evening, $kProfileFirst', style: CcText.h1),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onOpenProfiles,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Cc.olive, shape: BoxShape.circle),
                    child: const Text(kProfileInitial,
                        style: TextStyle(
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
                        painter: _RingPainter(kDietScore / 100),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$kDietScore',
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
                          Text(
                              'Up 4 points this week. Sodium is still the thing holding you back.',
                              style: CcText.body.copyWith(color: Cc.oliveDark, fontSize: 12.5)),
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
            const SizedBox(height: 14),

            // proactive nudge
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
                      decoration:
                          const BoxDecoration(color: Cc.accentDeep, shape: BoxShape.circle)),
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
                        Text(
                            "Three high-sodium scans in six days while you're on Telmisartan. "
                            "Nothing alarming yet — let's fix it early.",
                            style: CcText.body.copyWith(color: const Color(0xFF7A4A31))),
                        const SizedBox(height: 11),
                        Row(children: [
                          GestureDetector(
                            onTap: () => onNav?.call('nudge'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                              decoration: BoxDecoration(
                                  color: Cc.accentDeep, borderRadius: BorderRadius.circular(999)),
                              child: const Text("What's driving it",
                                  style: TextStyle(
                                      fontFamily: 'DMSans',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Text('Not now',
                                style: TextStyle(
                                    fontFamily: 'DMSans',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF8A4526))),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

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

            CcSectionHead('Today',
                trailing: 'All history →', onTrailing: () => onNav?.call('history')),
            const SizedBox(height: 10),
            for (final s in kTodayScans) ...[
              _ScanRow(scan: s),
              const SizedBox(height: 9),
            ],

            const SizedBox(height: 7),
            GestureDetector(
              onTap: () => onNav?.call('meds'),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                decoration: BoxDecoration(
                    color: const Color(0xFFEAEADB), borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Watching 4 medications',
                              style: TextStyle(
                                  fontFamily: 'Bricolage',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Cc.ink)),
                        ),
                        Text('Manage →',
                            style: CcText.bodySm
                                .copyWith(color: Cc.olive, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final m in kMeds)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
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
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CcBottomNav(
        active: 'home',
        onTapItem: onNav,
        onTapScan: onScan,
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

class _ScanRow extends StatelessWidget {
  const _ScanRow({required this.scan});
  final DemoScan scan;

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
          CcScoreChip(scan.score),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scan.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CcText.listTitle),
                const SizedBox(height: 2),
                Text(scan.note, style: CcText.bodySm.copyWith(color: Cc.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(scan.when, style: CcText.mono.copyWith(color: const Color(0xFFA3A491))),
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
