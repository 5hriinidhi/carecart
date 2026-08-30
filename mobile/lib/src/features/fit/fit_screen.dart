import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fit_api.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// CareCart Fit — the medical + lifestyle correlation screen. Overall score up
/// top, then a Lifestyle section and a Medicines section that move
/// independently (mirrors turns 1c / 1e of the design).
class FitScreen extends ConsumerWidget {
  const FitScreen({super.key, this.onClose, this.onEditLifestyle});
  final VoidCallback? onClose;
  final VoidCallback? onEditLifestyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fitProvider);
    return CcScreen(
      background: Cc.paper,
      child: async.when(
        loading: () => const Center(
            child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))),
        error: (_, _) => _Message(
            'Couldn’t load your Fit score.', onClose: onClose),
        data: (r) => switch (r) {
          FitFailed(:final message) => _Message(message, onClose: onClose),
          FitLoaded(:final fit) => _FitView(
              fit: fit, onClose: onClose, onEditLifestyle: onEditLifestyle),
        },
      ),
    );
  }
}

Color _band(int score) => score >= 75
    ? Cc.olive
    : (score >= 50 ? Cc.caution : Cc.avoid);

class _FitView extends StatelessWidget {
  const _FitView({required this.fit, this.onClose, this.onEditLifestyle});
  final Fit fit;
  final VoidCallback? onClose;
  final VoidCallback? onEditLifestyle;

  String get _summary {
    switch (fit.tier) {
      case 'well matched':
        return 'Your lifestyle and your recent scans line up well with what '
            'you’re managing.';
      case 'some tension':
        return 'A few things are pulling against each other. The section below '
            'shows where.';
      case 'needs attention':
        return 'Your recent choices are working against your meds or your '
            'health. Start with the focus card.';
      default:
        return 'Answer the lifestyle questions and scan a few labels to build '
            'this score.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = fit.score;
    final ink = score == null ? Cc.oliveDark : _bandInk(score);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
          decoration: BoxDecoration(
            color: score == null
                ? Cc.sageSoft
                : _band(score).withValues(alpha: 0.16),
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
                      onTap: onClose,
                      bg: Colors.white.withValues(alpha: 0.5),
                      size: 36),
                  Text('CARECART FIT',
                      style: CcText.mono.copyWith(
                          color: ink.withValues(alpha: 0.6),
                          fontSize: 11,
                          letterSpacing: 1.0)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(score?.toString() ?? '–',
                      key: const Key('fit-score'),
                      style: CcText.hero.copyWith(color: ink)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              (fit.tier ?? 'not enough data')
                                  .replaceFirstMapped(RegExp('^.'),
                                      (m) => m[0]!.toUpperCase()),
                              style: TextStyle(
                                  fontFamily: 'Bricolage',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: ink)),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('FIT /100',
                                  style: CcText.mono.copyWith(
                                      color: ink.withValues(alpha: 0.6),
                                      fontSize: 11)),
                              if (fit.delta != 0)
                                Text(
                                    '${fit.delta > 0 ? '+' : ''}${fit.delta} vs last 3 wks',
                                    style: CcText.mono.copyWith(
                                        color: fit.delta > 0
                                            ? Cc.oliveDark
                                            : Cc.avoid,
                                        fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_summary,
                  style: CcText.bodySm
                      .copyWith(color: ink.withValues(alpha: 0.9), height: 1.5)),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------- lifestyle ----------------
              _SectionHead(
                title: 'Lifestyle',
                trailing: fit.lifestyle.overall == null
                    ? null
                    : '${fit.lifestyle.overall}',
                sub: fit.lifestyle.answered == 0
                    ? 'Not answered yet'
                    : '${fit.lifestyle.answered} of ${fit.lifestyle.total} answered',
              ),
              const SizedBox(height: 12),
              if (fit.lifestyle.dims.isEmpty)
                _Empty(
                  'You haven’t answered the lifestyle questions yet.',
                  action: 'Answer them',
                  onAction: onEditLifestyle,
                )
              else
                for (final d in fit.lifestyle.dims) ...[
                  _Rail(
                      label: d.label,
                      score: d.score,
                      note: d.detail,
                      keyName: 'fit-life-${d.key}'),
                  const SizedBox(height: 10),
                ],

              const SizedBox(height: 14),
              // ---------------- medicines ----------------
              _SectionHead(
                title: 'Medicines',
                trailing: fit.medicines.overall == null
                    ? null
                    : '${fit.medicines.overall}',
                sub: fit.medicines.meds.isEmpty
                    ? 'No medications on file'
                    : 'Against your last ${fit.medicines.scansInWindow} scans (21 days)',
              ),
              const SizedBox(height: 12),
              if (fit.medicines.meds.isEmpty)
                _Empty(
                  'Add your medications and their food interactions show up here.',
                )
              else
                for (final m in fit.medicines.meds) ...[
                  _Rail(
                    label: m.name,
                    score: m.score,
                    note: m.note,
                    chips: m.interactions,
                    keyName: 'fit-med-${m.name}',
                  ),
                  const SizedBox(height: 10),
                ],

              if (fit.focus != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                      color: Cc.inkSoft,
                      borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WHERE TO FOCUS',
                          style: CcText.mono.copyWith(
                              color: Cc.sage,
                              fontSize: 10.5,
                              letterSpacing: 1.0)),
                      const SizedBox(height: 8),
                      Text(fit.focus!.message,
                          style: CcText.bodySm.copyWith(
                              color: Cc.paper, height: 1.55)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onEditLifestyle,
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: Cc.accent,
                            borderRadius: BorderRadius.circular(999)),
                        child: const Text('Update lifestyle',
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
                    onTap: onClose,
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
    );
  }
}

Color _bandInk(int score) => score >= 75
    ? const Color(0xFF243015)
    : (score >= 50 ? const Color(0xFF5A430A) : const Color(0xFF5E241A));

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, this.trailing, required this.sub});
  final String title;
  final String? trailing;
  final String sub;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CcText.h2),
                const SizedBox(height: 2),
                Text(sub,
                    style: CcText.bodySm
                        .copyWith(color: Cc.muted, fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(
                    fontFamily: 'Bricolage',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Cc.ink)),
        ],
      );
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.label,
    required this.score,
    required this.note,
    this.chips = const [],
    required this.keyName,
  });
  final String label;
  final int? score; // null -> "—" / not assessed
  final String note;
  final List<String> chips;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final s = score;
    final color = s == null ? Cc.muted : _band(s);
    return Container(
      key: Key(keyName),
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
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontFamily: 'Bricolage',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Cc.ink)),
              ),
              const SizedBox(width: 10),
              Text(s?.toString() ?? '–',
                  style: TextStyle(
                      fontFamily: 'Bricolage',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (s ?? 0) / 100,
              minHeight: 8,
              backgroundColor: const Color(0x14202419),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 9),
          Text(note,
              style: CcText.bodySm
                  .copyWith(color: const Color(0xFF4A4C3D), height: 1.45)),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: const Color(0x0F202419),
                        borderRadius: BorderRadius.circular(99)),
                    child: Text(c,
                        style: CcText.mono
                            .copyWith(color: Cc.muted, fontSize: 10)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text, {this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Cc.paperRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14151510)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text,
                style: CcText.bodySm.copyWith(color: Cc.muted, height: 1.5)),
            if (action != null) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: onAction,
                child: Text(action!,
                    style: CcText.bodySm.copyWith(
                        color: Cc.oliveDark, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onClose});
  final String text;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(text, textAlign: TextAlign.center, style: CcText.body),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onClose,
              child: Text('Back',
                  style: CcText.body.copyWith(
                      color: Cc.oliveDark, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
