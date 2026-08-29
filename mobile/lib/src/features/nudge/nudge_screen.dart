import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/notifications.dart';
import '../../core/nudges_api.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../state/main_app_state.dart';

/// Proactive check-in screen — `state.screen == 'nudge'`. Wired to GET /nudges
/// (Phase 5.3): shows the newest un-dismissed nudge and its actionable
/// suggestion. "Remind me" asks for notification permission *explicitly* first.
class NudgeScreen extends ConsumerStatefulWidget {
  const NudgeScreen({super.key, this.onHome});
  final VoidCallback? onHome;

  @override
  ConsumerState<NudgeScreen> createState() => _NudgeScreenState();
}

class _NudgeScreenState extends ConsumerState<NudgeScreen> {
  static const _bg = Color(0xFFF7E2D5);
  static const _rust = Color(0xFF8A4526);

  String? _note; // inline feedback under the action row
  bool _busy = false;
  bool _permissionDenied = false; // asked once, said no — don't nag

  static const _settingsHint =
      'Notifications are off. Turn them on for CareCart in your phone\'s '
      'Settings to get reminders.';

  static const _titles = <String, String>{
    'sodium': 'Sodium keeps turning up in your scans',
    'added_sugar': 'Added sugar is a recurring theme',
    'rapid_carb': 'Refined carbs keep coming up',
    'saturated_fat': 'Saturated fat is trending in your scans',
    'trans_fat': 'Trans fat showed up more than once',
    'vitamin_k': 'Your vitamin-K intake is swinging',
    'potassium': 'Potassium is a recurring flag',
    'caffeine': 'Caffeine keeps coming up',
    'tyramine': 'Aged / fermented foods are recurring',
    'milk_allergen': 'Hidden dairy keeps appearing',
    'gluten_allergen': 'Wheat / gluten is a recurring flag',
    'nut_allergen': 'Nut-allergen ingredients keep appearing',
    'alcohol': 'Alcohol-containing items are recurring',
  };

  Future<void> _remindMe(Nudge nudge) async {
    // Asked once and denied -> never re-prompt. Just re-show the settings hint;
    // the only way back is the OS settings screen.
    if (_permissionDenied) {
      setState(() => _note = _settingsHint);
      return;
    }
    setState(() => _busy = true);
    final notifs = ref.read(notificationServiceProvider);
    final granted = await notifs.requestPermission();
    if (!mounted) return;
    if (granted) {
      await notifs.showNudge(
          title: 'A pattern worth a look', body: nudge.message);
      ref.read(mainAppProvider.notifier).acceptNudge();
      setState(() {
        _busy = false;
        _note = "Done — we'll nudge you when this comes up again.";
      });
    } else {
      setState(() {
        _busy = false;
        _permissionDenied = true;
        _note = _settingsHint;
      });
    }
  }

  Future<void> _notNow(Nudge nudge) async {
    setState(() => _busy = true);
    await dismissNudge(ref.read(dioProvider), nudge.id);
    ref.invalidate(nudgesProvider);
    if (mounted) widget.onHome?.call();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(nudgesProvider);
    final Nudge? nudge = switch (async.asData?.value) {
      NudgesLoaded(:final page) when page.items.isNotEmpty => page.items.first,
      _ => null,
    };

    return CcScreen(
      background: _bg,
      safeBottom: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        children: [
          CcRoundButton(
              icon: Icons.close_rounded,
              onTap: widget.onHome,
              bg: Colors.white.withValues(alpha: 0.55),
              size: 36),
          const SizedBox(height: 18),
          Text('PROACTIVE CHECK-IN',
              style: CcText.mono
                  .copyWith(color: _rust, letterSpacing: 1.05, fontSize: 10.5)),
          const SizedBox(height: 10),
          if (async.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (nudge == null)
            _empty()
          else
            _nudge(nudge),
        ],
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nothing to flag right now',
                style: TextStyle(
                    fontFamily: 'Bricolage',
                    fontSize: 24,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Cc.inkSoft)),
            const SizedBox(height: 12),
            Text(
                'Keep scanning as you shop. If the same risk factor shows up in '
                '3+ scans over two weeks, a specific suggestion appears here.',
                style: CcText.body.copyWith(
                    color: const Color(0xFF5C3A26), fontSize: 13.5, height: 1.6)),
          ],
        ),
      );

  Widget _nudge(Nudge nudge) {
    final heading = _titles[nudge.factor] ??
        "'${nudge.factor.replaceAll('_', ' ')}' keeps coming up in your scans";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading,
            key: const Key('nudge-heading'),
            style: const TextStyle(
                fontFamily: 'Bricolage',
                fontSize: 25,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: Cc.inkSoft)),
        const SizedBox(height: 12),
        Text(
            'Flagged in ${nudge.hitCount} of your last ${nudge.windowDays} days '
            'of scans. Weekends are usually fine — this looks like a habit, '
            'which makes it a fixable one.',
            style: CcText.body.copyWith(
                color: const Color(0xFF5C3A26), fontSize: 13.5, height: 1.6)),
        const SizedBox(height: 20),
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
              Text(nudge.message,
                  key: const Key('nudge-message'),
                  style: CcText.body
                      .copyWith(color: Cc.paper, fontSize: 14, height: 1.55)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _busy ? null : () => _remindMe(nudge),
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: _permissionDenied
                                ? Cc.sage.withValues(alpha: 0.45)
                                : Cc.sage,
                            borderRadius: BorderRadius.circular(999)),
                        child: Text(_permissionDenied ? 'Notifications off' : 'Remind me',
                            style: const TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Cc.inkSoft)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  GestureDetector(
                    onTap: _busy ? null : () => _notNow(nudge),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      child: Text('Not now',
                          style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.7))),
                    ),
                  ),
                ],
              ),
              if (_note != null) ...[
                const SizedBox(height: 12),
                Text(_note!,
                    key: const Key('nudge-note'),
                    style: CcText.bodySm.copyWith(
                        color: Cc.sage, fontSize: 11.5, height: 1.45)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
