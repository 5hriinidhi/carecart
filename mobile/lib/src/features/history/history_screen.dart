import 'package:flutter/material.dart';

import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../fixtures/demo_data.dart';

/// Static food-history screen — `state.screen == 'history'`.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, this.onNav, this.onScan});
  final void Function(String route)? onNav;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Cc.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          children: [
            const SizedBox(height: 6),
            const Text('Food history', style: CcText.h1),
            const SizedBox(height: 4),
            Text('Every scan is kept locally. Export or wipe it any time.',
                style: CcText.body.copyWith(color: Cc.muted)),
            const SizedBox(height: 16),
            const Wrap(spacing: 7, runSpacing: 7, children: [
              CcPill('All', active: true),
              CcPill('Safe'),
              CcPill('Caution'),
              CcPill('Avoid'),
            ]),
            for (final g in kHistory) ...[
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(g.day.toUpperCase(),
                        style: CcText.label.copyWith(
                            color: const Color(0xFFA3A491), letterSpacing: 1.05)),
                  ),
                  Text('day score ${g.dayScore}',
                      style: CcText.bodySm.copyWith(color: const Color(0xFFA3A491))),
                ],
              ),
              const SizedBox(height: 9),
              for (final i in g.items) ...[
                _HistoryRow(scan: i),
                const SizedBox(height: 9),
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar:
          CcBottomNav(active: 'history', onTapItem: onNav, onTapScan: onScan),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.scan});
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
          Text(scan.when,
              style: CcText.mono.copyWith(color: const Color(0xFFA3A491))),
        ],
      ),
    );
  }
}
