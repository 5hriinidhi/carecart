import 'package:flutter/material.dart';

import '../../core/severity.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../fixtures/demo_data.dart';

/// Static trends screen — `state.screen == 'trends'`. Frozen on the 7-day range.
class TrendsScreen extends StatelessWidget {
  const TrendsScreen({super.key, this.range = '7d', this.onNav, this.onScan});
  final String range;
  final void Function(String route)? onNav;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final series = kTrend[range]!;
    final labels = kTrendLabels[range]!;

    return Scaffold(
      backgroundColor: Cc.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          children: [
            const SizedBox(height: 6),
            const Text('Your trend', style: CcText.h1),
            const SizedBox(height: 4),
            Text('Built from 46 scans. No manual logging.',
                style: CcText.body.copyWith(color: Cc.muted)),
            const SizedBox(height: 16),
            Wrap(spacing: 7, children: [
              CcPill('Last 7 days', active: range == '7d'),
              CcPill('30 days', active: range == '30d'),
              CcPill('90 days', active: range == '90d'),
            ]),
            const SizedBox(height: 14),

            // score card + line chart
            Container(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              decoration: BoxDecoration(
                color: Cc.paperRaised,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0x12151510)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Diet Health Score',
                                style: TextStyle(
                                    fontFamily: 'Bricolage',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Cc.ink)),
                            const SizedBox(height: 3),
                            Text(kRangeLabels[range]!,
                                style: CcText.bodySm.copyWith(color: Cc.muted)),
                          ],
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          const Text('$kDietScore',
                              style: TextStyle(
                                  fontFamily: 'Bricolage',
                                  fontSize: 30,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                  color: Cc.ink)),
                          const SizedBox(width: 7),
                          Text('+4',
                              style: CcText.mono.copyWith(
                                  color: const Color(0xFF4A5A33), fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: CustomPaint(painter: _LineChartPainter(series)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final l in labels)
                        Text(l,
                            style: CcText.mono.copyWith(
                                fontSize: 10, color: const Color(0xFFA3A491))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            const Text('Nutrient trajectories', style: CcText.h2),
            const SizedBox(height: 12),
            for (final j in kTrajectories) ...[
              _TrajectoryCard(t: j),
              const SizedBox(height: 10),
            ],

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(18),
              decoration:
                  BoxDecoration(color: Cc.sage, borderRadius: BorderRadius.circular(22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WHAT CHANGED',
                      style: CcText.mono.copyWith(
                          color: Cc.oliveDark, letterSpacing: 1.05, fontSize: 10.5)),
                  const SizedBox(height: 9),
                  Text(
                      'You swapped instant noodles for millet noodles four times this month. '
                      'That single habit accounts for most of your +4.',
                      style: CcText.body.copyWith(
                          color: Cc.inkSoft, fontSize: 14, height: 1.55)),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          CcBottomNav(active: 'trends', onTapItem: onNav, onTapScan: onScan),
    );
  }
}

class _TrajectoryCard extends StatelessWidget {
  const _TrajectoryCard({required this.t});
  final DemoTrajectory t;

  @override
  Widget build(BuildContext context) {
    final s = chipFor(_score(t.tone));
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x12151510)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(t.k,
                    style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Cc.ink)),
              ),
              Text(t.delta,
                  style: CcText.mono.copyWith(color: s.color, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 11),
          SizedBox(
            height: 38,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < t.bars.length; i++)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 38 * t.bars[i] / 100,
                      decoration: BoxDecoration(
                        color: i == t.bars.length - 1 ? s.color : s.tint,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Text(t.note, style: CcText.bodySm.copyWith(color: Cc.muted, height: 1.45)),
        ],
      ),
    );
  }

  static int _score(Severity s) => switch (s) {
        Severity.avoid => 20,
        Severity.caution => 50,
        Severity.safe => 85,
      };
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.series);
  final List<int> series;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x14202419)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height * .25), Offset(size.width, size.height * .25), grid);
    canvas.drawLine(Offset(0, size.height * .62), Offset(size.width, size.height * .62), grid);

    final pts = <Offset>[];
    for (var i = 0; i < series.length; i++) {
      final x = i / (series.length - 1) * size.width;
      final y = size.height - ((series[i] - 35) / 55) * size.height * 0.9;
      pts.add(Offset(x, y.clamp(0, size.height)));
    }

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = const Color(0x2463753F));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = Cc.olive);
    for (var i = 0; i < pts.length; i++) {
      canvas.drawCircle(
          pts[i],
          i == pts.length - 1 ? 5 : 3,
          Paint()..color = i == pts.length - 1 ? Cc.accent : Cc.olive);
      canvas.drawCircle(
          pts[i],
          i == pts.length - 1 ? 5 : 3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Cc.paperRaised);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => old.series != series;
}
