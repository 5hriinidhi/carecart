import 'package:flutter/material.dart';

import '../../core/severity.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../fixtures/demo_data.dart';

/// Static verdict / result screen — `state.screen == 'result'`.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, this.productId = 'noodles', this.onHome, this.onScan});
  final String productId;
  final VoidCallback? onHome;
  final VoidCallback? onScan;

  Color get _ink => switch (kProducts[productId]!.verdict) {
        Severity.avoid => const Color(0xFF5E241A),
        Severity.caution => const Color(0xFF5A430A),
        Severity.safe => const Color(0xFF243015),
      };

  @override
  Widget build(BuildContext context) {
    final p = kProducts[productId]!;
    final sev = chipFor(p.score);

    return CcScreen(
      background: Cc.paper,
      child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // hero
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
              decoration: BoxDecoration(
                color: sev.tint,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CcRoundButton(
                          icon: Icons.close_rounded,
                          onTap: onHome,
                          bg: Colors.white.withValues(alpha: 0.5),
                          size: 36),
                      Row(
                        children: [
                          for (final t in Severity.values)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              width: t == p.verdict ? 26 : 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: t == p.verdict
                                    ? chipFor(_scoreFor(t)).color
                                    : const Color(0x38202419),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${p.score}',
                          style: CcText.hero.copyWith(color: _ink)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.verdictLabel,
                                  style: TextStyle(
                                      fontFamily: 'Bricolage',
                                      fontSize: 19,
                                      height: 1.1,
                                      fontWeight: FontWeight.w700,
                                      color: _ink)),
                              const SizedBox(height: 4),
                              Text('CARECART SCORE /100',
                                  style: CcText.mono.copyWith(
                                      color: _ink.withValues(alpha: 0.65), fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(p.summary,
                      style: CcText.body.copyWith(
                          color: _ink.withValues(alpha: 0.85), fontSize: 13.5, height: 1.5)),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        const CcThumb(),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: CcText.listTitle),
                              const SizedBox(height: 2),
                              Text('${p.brand} · ${p.serving}',
                                  style: CcText.bodySm
                                      .copyWith(color: const Color(0x99202419))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.flagsHeading, style: CcText.h2),
                  const SizedBox(height: 4),
                  Text(
                      "Checked against $kProfileFirst's conditions and 4 active medications.",
                      style: CcText.bodySm.copyWith(color: Cc.muted, fontSize: 12)),
                  const SizedBox(height: 14),
                  for (final f in p.flags) ...[
                    _FlagCard(flag: f),
                    const SizedBox(height: 10),
                  ],

                  const SizedBox(height: 14),
                  const Text('Per serving, against your ceilings', style: CcText.h2),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Cc.paperRaised,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0x12151510)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final n in p.nutrients) ...[
                          _NutrientRow(n: n),
                          const SizedBox(height: 14),
                        ],
                        Text('Ceilings derived from your profile, not generic RDA.',
                            style: CcText.bodySm
                                .copyWith(color: const Color(0xFFA3A491), fontSize: 11)),
                      ],
                    ),
                  ),

                  if (p.swaps.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('Safer swaps, same shelf', style: CcText.h2),
                    const SizedBox(height: 4),
                    Text('Ranked on your conditions first, then on what you actually buy.',
                        style: CcText.bodySm.copyWith(color: Cc.muted, fontSize: 12)),
                    const SizedBox(height: 14),
                    for (final s in p.swaps) ...[
                      _SwapRow(swap: s),
                      const SizedBox(height: 10),
                    ],
                  ],

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(15),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: Cc.accent, borderRadius: BorderRadius.circular(999)),
                          child: const Text('Log this to history',
                              style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Cc.inkSoft)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: onScan,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          decoration: BoxDecoration(
                            color: Cc.paperRaised,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0x1F151510)),
                          ),
                          child: const Text('Scan next',
                              style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Cc.ink)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  static int _scoreFor(Severity t) => switch (t) {
        Severity.avoid => 20,
        Severity.caution => 50,
        Severity.safe => 85,
      };
}

class _FlagCard extends StatelessWidget {
  const _FlagCard({required this.flag});
  final DemoFlag flag;

  @override
  Widget build(BuildContext context) {
    final s = chipFor(_score(flag.sev));
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: s.color, width: 4)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
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
                child: Text(flag.title,
                    style: const TextStyle(
                        fontFamily: 'Bricolage',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Cc.ink)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration:
                    BoxDecoration(color: s.tint, borderRadius: BorderRadius.circular(99)),
                child: Text(flag.tag,
                    style: CcText.mono.copyWith(color: s.color, fontSize: 10.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(flag.why,
              style: CcText.body.copyWith(color: const Color(0xFF4A4C3D), height: 1.55)),
          if (flag.alias != null) ...[
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                  color: const Color(0x0D202419), borderRadius: BorderRadius.circular(9)),
              child: Text('also labelled: ${flag.alias}',
                  style: CcText.mono.copyWith(fontSize: 11, letterSpacing: 0)),
            ),
          ],
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

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({required this.n});
  final DemoNutrient n;

  @override
  Widget build(BuildContext context) {
    final color = chipFor(_score(n.tone)).color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 3,
              child: Text(n.k,
                  style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Cc.ink)),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Text('${n.v} · ${n.pct}% of ceiling',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: CcText.mono.copyWith(color: color, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        CcMeter(pct: n.pct, color: color),
      ],
    );
  }

  static int _score(Severity s) => switch (s) {
        Severity.avoid => 20,
        Severity.caution => 50,
        Severity.safe => 85,
      };
}

class _SwapRow extends StatelessWidget {
  const _SwapRow({required this.swap});
  final DemoSwap swap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(color: Cc.safeTint, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          const CcThumb(size: 44, radius: 12),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(swap.name, style: CcText.listTitle.copyWith(color: Cc.inkSoft)),
                const SizedBox(height: 3),
                Text(swap.note,
                    style: CcText.bodySm.copyWith(color: const Color(0xFF4A5A33))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${swap.score}',
              style: const TextStyle(
                  fontFamily: 'Bricolage',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Cc.oliveDark)),
        ],
      ),
    );
  }
}
