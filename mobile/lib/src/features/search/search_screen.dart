import 'package:flutter/material.dart';

import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../fixtures/demo_data.dart';

/// Static search screen — `state.screen == 'search'`.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key, this.onBack, this.showEmpty = false});
  final VoidCallback? onBack;
  final bool showEmpty; // preview the "not in the database yet" state

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Cc.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          children: [
            const SizedBox(height: 6),
            Row(
              children: [
                CcRoundButton(
                    icon: Icons.arrow_back_ios_new_rounded, onTap: onBack, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                    decoration: BoxDecoration(
                      color: Cc.paperRaised,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x1F151510)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, size: 16, color: Cc.muted),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text('Product, brand or ingredient',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CcText.bodySm.copyWith(
                                  color: const Color(0xFFA3A491), fontSize: 13.5)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (showEmpty)
              _EmptyState()
            else ...[
              Text('RECENTLY SCANNED NEAR YOU',
                  style: CcText.mono.copyWith(
                      color: const Color(0xFFA3A491), letterSpacing: 1.05, fontSize: 10.5)),
              const SizedBox(height: 10),
              for (final s in kSearchRecent) ...[
                _ResultRow(hit: s),
                const SizedBox(height: 9),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.hit});
  final DemoSearchHit hit;

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
          const CcThumb(size: 42, radius: 11),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hit.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: CcText.listTitle),
                const SizedBox(height: 2),
                Text(hit.brand, style: CcText.bodySm.copyWith(color: Cc.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CcScoreChip(hit.score),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 34, 20, 34),
      child: Column(
        children: [
          const Text('Not in the database yet',
              style: TextStyle(
                  fontFamily: 'Bricolage',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Cc.ink)),
          const SizedBox(height: 6),
          Text(
              "Scan the ingredients list and we'll read it directly — and add it for everyone else.",
              textAlign: TextAlign.center,
              style: CcText.body.copyWith(color: Cc.muted)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
                color: Cc.accent, borderRadius: BorderRadius.circular(999)),
            child: const Text('Scan the label',
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Cc.inkSoft)),
          ),
        ],
      ),
    );
  }
}
