import 'package:flutter/material.dart';

import '../../core/product_api.dart';
import '../../core/severity.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../fixtures/demo_data.dart';

/// Verdict / result screen — `state.screen == 'result'`.
///
/// There is ONE rendering path now: the [ScanVerdict] shape returned by
/// `POST /scan/verdict`. A real barcode scan passes its live [verdict]; the
/// Phase 2 demo picker passes only a [productId] and the fixture is adapted
/// into the same shape by [demoVerdict] — so the screen is always driven by the
/// real response contract, and the tier always comes from [chipFor].
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    this.productId = 'noodles',
    this.verdict,
    this.productName,
    this.onHome,
    this.onScan,
  });

  final String productId;
  final ScanVerdict? verdict;
  final String? productName;
  final VoidCallback? onHome;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final v = verdict ?? demoVerdict(productId);
    return _LiveVerdictView(
      verdict: v,
      productName: productName ?? kProducts[productId]?.name,
      onHome: onHome,
      onScan: onScan,
    );
  }
}

/// Adapt a Phase 2 [DemoProduct] fixture into the real [ScanVerdict] shape so
/// the demo picker and a live scan render through the exact same widget. The
/// tier is derived from [chipFor] (Phase 2.1), never a hand-set field.
ScanVerdict demoVerdict(String productId) {
  final p = kProducts[productId] ?? kProducts['noodles']!;

  String kindFor(Severity s) => switch (s) {
        Severity.avoid => 'drug_interaction',
        Severity.caution => 'condition_ceiling',
        Severity.safe => 'clear',
      };
  String sevName(Severity s) => switch (s) {
        Severity.avoid => 'high',
        Severity.caution => 'moderate',
        Severity.safe => 'info',
      };

  final reasons = <VerdictReason>[
    for (final f in p.flags)
      VerdictReason(
        kind: kindFor(f.sev),
        severity: sevName(f.sev),
        points: 0,
        title: f.title,
        detail: [
          f.why,
          if (f.alias != null) 'also labelled: ${f.alias}',
        ].join('  '),
      ),
  ];
  if (reasons.isEmpty) {
    reasons.add(const VerdictReason(
      kind: 'clear',
      severity: 'info',
      points: 0,
      title: 'No conflicts found with your medications, conditions, or allergies.',
    ));
  }

  return ScanVerdict(
    score: p.score,
    tier: chipFor(p.score).tone.name, // safe | caution | avoid — from chipFor()
    hardStop: false,
    reasons: reasons,
  );
}

// ===========================================================================
// The one verdict view — real score / tier / reasons from POST /scan/verdict
// ===========================================================================

class _LiveVerdictView extends StatelessWidget {
  const _LiveVerdictView({
    required this.verdict,
    this.productName,
    this.onHome,
    this.onScan,
  });

  final ScanVerdict verdict;
  final String? productName;
  final VoidCallback? onHome;
  final VoidCallback? onScan;

  Color get _ink => switch (chipFor(verdict.score).tone) {
        Severity.avoid => const Color(0xFF5E241A),
        Severity.caution => const Color(0xFF5A430A),
        Severity.safe => const Color(0xFF243015),
      };

  @override
  Widget build(BuildContext context) {
    final sev = chipFor(verdict.score);
    final activeMeds = verdict.medications.length;

    return CcScreen(
      background: Cc.paper,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
            decoration: BoxDecoration(
              color: sev.tint,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(28)),
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
                    if (verdict.hardStop)
                      Container(
                        key: const Key('verdict-hardstop-badge'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Cc.avoid,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text('ALLERGEN — HARD STOP',
                            style: CcText.mono
                                .copyWith(color: Colors.white, fontSize: 10.5)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${verdict.score}',
                        key: const Key('verdict-score'),
                        style: CcText.hero.copyWith(color: _ink)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sev.label,
                                key: const Key('verdict-tier'),
                                style: TextStyle(
                                    fontFamily: 'Bricolage',
                                    fontSize: 19,
                                    height: 1.1,
                                    fontWeight: FontWeight.w700,
                                    color: _ink)),
                            const SizedBox(height: 4),
                            Text('CARECART SCORE /100',
                                style: CcText.mono.copyWith(
                                    color: _ink.withValues(alpha: 0.65),
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (productName != null && productName!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        const CcThumb(),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(productName!, style: CcText.listTitle),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Why this verdict', style: CcText.h2),
                const SizedBox(height: 4),
                Text(
                  activeMeds == 0
                      ? 'Checked against your conditions, allergies and medications.'
                      : 'Checked against your conditions, allergies and '
                          '$activeMeds active medication${activeMeds == 1 ? '' : 's'}.',
                  style: CcText.bodySm.copyWith(color: Cc.muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                for (final r in verdict.reasons) ...[
                  _ReasonCard(reason: r),
                  const SizedBox(height: 10),
                ],
                if (verdict.medications.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Medications checked', style: CcText.h2),
                  const SizedBox(height: 10),
                  for (final m in verdict.medications)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        m.identified
                            ? '• ${m.name} — ${m.drugClasses.join(", ")}'
                            : '• ${m.name} — not identified, not checked for interactions',
                        style: CcText.bodySm.copyWith(
                            color: m.identified ? Cc.ink : Cc.caution,
                            fontSize: 12.5),
                      ),
                    ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onScan,
                        child: Container(
                          padding: const EdgeInsets.all(15),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: Cc.accent,
                              borderRadius: BorderRadius.circular(999)),
                          child: const Text('Scan next',
                              style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Cc.inkSoft)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onHome,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 15),
                        decoration: BoxDecoration(
                          color: Cc.paperRaised,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x1F151510)),
                        ),
                        child: const Text('Home',
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
}

class _ReasonCard extends StatelessWidget {
  const _ReasonCard({required this.reason});
  final VerdictReason reason;

  Color get _accent => switch (reason.severity) {
        'high' => Cc.avoid,
        'moderate' => Cc.caution,
        'low' => Cc.olive,
        _ => Cc.sage,
      };

  @override
  Widget build(BuildContext context) {
    final tag = reason.isAllergen
        ? 'STOP'
        : reason.points > 0
            ? '−${reason.points}'
            : reason.kind.toUpperCase();
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: _accent, width: 4)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 3),
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: _accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(reason.title,
                    style: const TextStyle(
                        fontFamily: 'Bricolage',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: Cc.ink)),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99)),
                child: Text(tag,
                    style: CcText.mono.copyWith(color: _accent, fontSize: 10.5)),
              ),
            ],
          ),
          if (reason.detail != null && reason.detail!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(reason.detail!,
                style: CcText.body
                    .copyWith(color: const Color(0xFF4A4C3D), height: 1.55)),
          ],
        ],
      ),
    );
  }
}
