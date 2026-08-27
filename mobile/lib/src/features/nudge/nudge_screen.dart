import 'package:flutter/material.dart';

import '../../core/severity.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../fixtures/demo_data.dart';

/// Static proactive check-in screen — `state.screen == 'nudge'`.
class NudgeScreen extends StatelessWidget {
  const NudgeScreen({super.key, this.onHome});
  final VoidCallback? onHome;

  static const _bg = Color(0xFFF7E2D5);
  static const _rust = Color(0xFF8A4526);

  @override
  Widget build(BuildContext context) {
    return CcScreen(
      background: _bg,
      safeBottom: true,
      child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          children: [
            CcRoundButton(
                icon: Icons.close_rounded,
                onTap: onHome,
                bg: Colors.white.withValues(alpha: 0.55),
                size: 36),
            const SizedBox(height: 18),
            Text('PROACTIVE CHECK-IN',
                style: CcText.mono
                    .copyWith(color: _rust, letterSpacing: 1.05, fontSize: 10.5)),
            const SizedBox(height: 10),
            const Text('Sodium is creeping up on your weekday lunches',
                style: TextStyle(
                    fontFamily: 'Bricolage',
                    fontSize: 26,
                    height: 1.18,
                    fontWeight: FontWeight.w700,
                    color: Cc.inkSoft)),
            const SizedBox(height: 12),
            Text(
                "You're averaging 2,340 mg on Tue–Thu against a 1,800 mg ceiling. "
                "Weekends are fine. This looks like a lunch-habit problem, not a "
                "diet problem — which makes it an easy fix.",
                style: CcText.body.copyWith(
                    color: const Color(0xFF5C3A26), fontSize: 13.5, height: 1.6)),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              decoration: BoxDecoration(
                  color: Cc.paperRaised, borderRadius: BorderRadius.circular(22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('The three scans behind this',
                      style: TextStyle(
                          fontFamily: 'Bricolage',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Cc.ink)),
                  const SizedBox(height: 12),
                  for (var i = 0; i < kNudgeScans.length; i++) ...[
                    _NudgeScanRow(scan: kNudgeScans[i]),
                    if (i != kNudgeScans.length - 1) const SizedBox(height: 9),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: Cc.inkSoft, borderRadius: BorderRadius.circular(22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ONE CHANGE TO TRY',
                      style: CcText.mono.copyWith(
                          color: Cc.sage, letterSpacing: 1.05, fontSize: 10.5)),
                  const SizedBox(height: 9),
                  Text(
                      'Move the instant noodles to millet noodles on Tue–Thu. '
                      'Modelled effect: −680 mg sodium a day, +6 on your score in three weeks.',
                      style: CcText.body.copyWith(
                          color: Cc.paper, fontSize: 14, height: 1.55)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(13),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: Cc.sage,
                              borderRadius: BorderRadius.circular(999)),
                          child: const Text('Remind me at lunch',
                              style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Cc.inkSoft)),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        child: Text('Later',
                            style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.7))),
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

class _NudgeScanRow extends StatelessWidget {
  const _NudgeScanRow({required this.scan});
  final DemoScan scan;

  @override
  Widget build(BuildContext context) {
    final s = chipFor(scan.score);
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: s.tint, borderRadius: BorderRadius.circular(10)),
          child: Text('${scan.score}',
              style: TextStyle(
                  fontFamily: 'Bricolage',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: s.color)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(scan.name,
                  style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Cc.ink)),
              const SizedBox(height: 2),
              Text(scan.note,
                  style: CcText.bodySm.copyWith(color: Cc.muted, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(scan.when,
            style: CcText.mono.copyWith(color: const Color(0xFFA3A491))),
      ],
    );
  }
}
