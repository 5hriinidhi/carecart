import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics_api.dart';
import '../../core/severity.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../fixtures/demo_data.dart';

/// Trends screen — `state.screen == 'trends'`. The Diet Health Score card + line
/// chart are wired to `GET /analytics/trends` (Phase 5.2); the older
/// TREND / TREND_LABELS fixtures are gone. (The nutrient-trajectory section is
/// still fixture-backed — a separate future feature.)
class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key, this.range = '7d', this.onNav, this.onScan});
  final String range;
  final void Function(String route)? onNav;
  final VoidCallback? onScan;

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  bool _monthly = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trendsProvider);
    final loaded = async.asData?.value;
    final trends = loaded is TrendsLoaded ? loaded.trends : null;
    final subtitle = trends != null
        ? 'Built from ${trends.totalScans} scan${trends.totalScans == 1 ? '' : 's'}. '
            'No manual logging.'
        : 'Built automatically from every scan.';

    return CcScreen(
      background: Cc.paper,
      child: ListView(
        primary: false,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        children: [
          const SizedBox(height: 6),
          const Text('Your trend', style: CcText.h1),
          const SizedBox(height: 4),
          Text(subtitle, style: CcText.body.copyWith(color: Cc.muted)),
          const SizedBox(height: 16),
          Wrap(spacing: 7, children: [
            GestureDetector(
              onTap: () => setState(() => _monthly = false),
              child: CcPill('Weekly', active: !_monthly),
            ),
            GestureDetector(
              onTap: () => setState(() => _monthly = true),
              child: CcPill('Monthly', active: _monthly),
            ),
          ]),
          const SizedBox(height: 14),

          _ScoreCard(
            state: async,
            monthly: _monthly,
            onScan: widget.onScan,
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
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.state, required this.monthly, this.onScan});
  final AsyncValue<TrendsResult> state;
  final bool monthly;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x12151510)),
      ),
      child: state.when(
        loading: () => const SizedBox(
          height: 150,
          child: Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2))),
        ),
        error: (e, _) => _message("Couldn't load your trends."),
        data: (r) => switch (r) {
          TrendsFailed(:final message) => _message(message, onScan: onScan),
          TrendsLoaded(:final trends) when trends.isEmpty => _message(
              'Scan a few products — your Diet Health Score and weekly trend '
              'show up here.',
              onScan: onScan),
          TrendsLoaded(:final trends) => _loaded(context, trends),
        },
      ),
    );
  }

  Widget _message(String text, {VoidCallback? onScan}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: CcText.body.copyWith(color: Cc.muted, height: 1.5)),
            if (onScan != null) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onScan,
                child: Text('Scan something →',
                    style: CcText.bodySm.copyWith(
                        color: Cc.olive, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      );

  Widget _loaded(BuildContext context, Trends trends) {
    final buckets = monthly ? trends.monthly : trends.weekly;
    final delta = trends.deltaSevenDay;
    final deltaColor = delta > 0
        ? const Color(0xFF4A5A33)
        : delta < 0
            ? Cc.avoid
            : Cc.muted;

    final safe = buckets.fold<int>(0, (s, b) => s + b.safe);
    final caution = buckets.fold<int>(0, (s, b) => s + b.caution);
    final avoid = buckets.fold<int>(0, (s, b) => s + b.avoid);

    final latest = buckets.isNotEmpty ? buckets.last : null;
    final skewed = latest != null && latest.meanSkewed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Text('Diet Health Score',
                  style: TextStyle(
                      fontFamily: 'Bricolage',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Cc.ink)),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${trends.dietHealthScore}',
                    key: const Key('dhs-value'),
                    style: const TextStyle(
                        fontFamily: 'Bricolage',
                        fontSize: 30,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: Cc.ink)),
                const SizedBox(width: 7),
                Text(delta == 0 ? '±0' : (delta > 0 ? '+$delta' : '$delta'),
                    key: const Key('dhs-delta'),
                    style: CcText.mono.copyWith(color: deltaColor, fontSize: 12)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text('${trends.trend} · 7-day change · ${trends.timezone}',
            style: CcText.bodySm.copyWith(color: Cc.muted)),
        const SizedBox(height: 16),
        SizedBox(
          height: 132,
          child: buckets.length < 2
              ? Center(
                  child: Text('Not enough history yet for a ${monthly ? 'monthly' : 'weekly'} line.',
                      style: CcText.bodySm.copyWith(color: Cc.muted)))
              : _DhsLineChart(buckets: buckets),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _TierChip('Safe', safe, Cc.safe, Cc.safeTint),
            const SizedBox(width: 8),
            _TierChip('Caution', caution, Cc.caution, Cc.cautionTint),
            const SizedBox(width: 8),
            _TierChip('Avoid', avoid, Cc.avoid, Cc.avoidTint),
          ],
        ),
        if (skewed) ...[
          const SizedBox(height: 12),
          _SkewNote(latest),
        ],
      ],
    );
  }
}

/// Shown when one unusual scan is dragging a bucket's mean away from its median,
/// so "average 71" doesn't read as "a bad week". The line chart plots the Diet
/// Health Score (an EMA), which already resists this.
class _SkewNote extends StatelessWidget {
  const _SkewNote(this.b);
  final TrendBucket b;

  @override
  Widget build(BuildContext context) {
    final low = b.avgScore < b.medianScore;
    final extreme = low ? b.minScore : b.maxScore;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Cc.cautionTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        key: const Key('trend-skew-note'),
        low
            ? 'One low scan ($extreme) pulled ${b.label}\'s average to '
                '${b.avgScore.toStringAsFixed(0)}. Most scans that week were '
                'nearer ${b.medianScore.toStringAsFixed(0)}.'
            : 'One high scan ($extreme) lifted ${b.label}\'s average to '
                '${b.avgScore.toStringAsFixed(0)}. Most scans that week were '
                'nearer ${b.medianScore.toStringAsFixed(0)}.',
        style: CcText.bodySm.copyWith(color: Cc.oliveDark, height: 1.45),
      ),
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip(this.label, this.count, this.fg, this.bg);
  final String label;
  final int count;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text('$count',
                key: Key('tier-$label-count'),
                style: TextStyle(
                    fontFamily: 'Bricolage',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: fg)),
            Text(label,
                style: CcText.mono.copyWith(fontSize: 9.5, color: fg)),
          ],
        ),
      ),
    );
  }
}

class _DhsLineChart extends StatelessWidget {
  const _DhsLineChart({required this.buckets});
  final List<TrendBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < buckets.length; i++)
        FlSpot(i.toDouble(), buckets[i].dietHealthScore.toDouble()),
    ];
    final lastX = (buckets.length - 1).toDouble();
    // show at most ~4 x labels so they don't collide
    final step = (buckets.length / 4).ceil().clamp(1, buckets.length);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: lastX,
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (v) => FlLine(
            color: (v == 45 || v == 70)
                ? const Color(0x33202419) // tier thresholds
                : const Color(0x14202419),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 50,
              reservedSize: 26,
              getTitlesWidget: (v, _) => Text('${v.toInt()}',
                  style: CcText.mono.copyWith(
                      fontSize: 9, color: const Color(0xFFA3A491))),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 20,
              getTitlesWidget: (v, _) {
                final i = v.round();
                if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
                if (i != 0 && i != buckets.length - 1 && i % step != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(buckets[i].label,
                      style: CcText.mono.copyWith(
                          fontSize: 9, color: const Color(0xFFA3A491))),
                );
              },
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            barWidth: 2.5,
            color: Cc.olive,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: spot.x == lastX ? 4 : 2.5,
                color: spot.x == lastX ? Cc.accent : Cc.olive,
                strokeWidth: 2,
                strokeColor: Cc.paperRaised,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0x2263753F),
            ),
          ),
        ],
      ),
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
