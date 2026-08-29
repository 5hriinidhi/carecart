import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/history_api.dart';
import '../../core/severity.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Food-history screen — `state.screen == 'history'`. Wired to `GET /history`
/// (Phase 5.1); every completed verdict writes a row server-side, so this is
/// just a read. Grouped by local day, newest first.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, this.onNav, this.onScan});
  final void Function(String route)? onNav;
  final VoidCallback? onScan;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _filter = 'All';

  static const _tierFor = {'All': null, 'Safe': 'safe', 'Caution': 'caution', 'Avoid': 'avoid'};

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(historyPageProvider);

    return CcScreen(
      background: Cc.paper,
      child: ListView(
        primary: false,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        children: [
          const SizedBox(height: 6),
          const Text('Food history', style: CcText.h1),
          const SizedBox(height: 4),
          Text('Every scan is logged automatically and encrypted at rest.',
              style: CcText.body.copyWith(color: Cc.muted)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final f in _tierFor.keys)
                GestureDetector(
                  onTap: () => setState(() => _filter = f),
                  child: CcPill(f, active: _filter == f),
                ),
            ],
          ),
          const SizedBox(height: 4),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, _) => _note("Couldn't load your history."),
            data: (r) => switch (r) {
              HistoryFailed(:final message) => _note(message),
              HistoryOffline(:final items, :final cachedAt) => _list(
                  items,
                  banner: _OfflineBanner(cachedAt: cachedAt),
                ),
              HistoryLoaded(:final page) => _list(page.items),
            },
          ),
        ],
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Text(text, style: CcText.body.copyWith(color: Cc.muted, height: 1.5)),
      );

  Widget _list(List<ScanHistoryEntry> allItems, {Widget? banner}) {
    final want = _tierFor[_filter];
    final items = [
      for (final e in allItems)
        if (want == null || e.tier == want) e,
    ];

    if (allItems.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note('No scans yet. Everything you check shows up here.'),
          if (widget.onScan != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              key: const Key('history-empty-scan'),
              onTap: widget.onScan,
              child: Text('Scan something →',
                  style: CcText.bodySm
                      .copyWith(color: Cc.olive, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      );
    }
    if (items.isEmpty) {
      return _note('Nothing in "$_filter" yet.');
    }

    // group by local calendar day
    final groups = <String, List<ScanHistoryEntry>>{};
    for (final e in items) {
      groups.putIfAbsent(_dayLabel(e.scannedAt), () => []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (banner != null) ...[const SizedBox(height: 10), banner],
        for (final entry in groups.entries) ...[
          const SizedBox(height: 18),
          Text(entry.key.toUpperCase(),
              key: Key('history-day-${entry.key}'),
              style: CcText.label.copyWith(
                  color: const Color(0xFFA3A491), letterSpacing: 1.05)),
          const SizedBox(height: 9),
          for (final e in entry.value) ...[
            _HistoryRow(entry: e),
            const SizedBox(height: 9),
          ],
        ],
      ],
    );
  }

  String _dayLabel(DateTime dtUtc) {
    final d = dtUtc.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]}';
  }
}

/// "Offline — showing saved history" strip. Distinct from a hard error: the
/// rows below it are real (last-synced) data, not a failure.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.cachedAt});
  final DateTime cachedAt;

  String get _ago {
    final d = DateTime.now().difference(cachedAt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('history-offline-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7E2D5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 16, color: Color(0xFF8A4526)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              "Offline — showing your saved history (synced $_ago). "
              "It'll refresh when you're back online.",
              style: CcText.bodySm
                  .copyWith(color: const Color(0xFF7A4A31), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});
  final ScanHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final s = chipFor(entry.score);
    final subtitle = entry.hardStop
        ? 'Allergen — hard stop'
        : (entry.keyReasons.isNotEmpty
            ? entry.keyReasons.first.title
            : '${s.tone.name[0].toUpperCase()}${s.tone.name.substring(1)} for you');
    final t = entry.scannedAt.toLocal();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x12151510)),
      ),
      child: Row(
        children: [
          CcScoreChip(entry.score),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.productName.isEmpty ? 'Scanned product' : entry.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CcText.listTitle),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CcText.bodySm.copyWith(color: Cc.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('$hh:$mm',
              style: CcText.mono.copyWith(color: const Color(0xFFA3A491))),
        ],
      ),
    );
  }
}
