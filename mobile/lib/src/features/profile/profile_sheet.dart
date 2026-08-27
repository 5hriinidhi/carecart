import 'package:flutter/material.dart';

import '../../core/text.dart';
import '../../core/theme.dart';
import '../../fixtures/demo_data.dart';

/// The "Who are we shopping for?" bottom sheet — `state.showProfiles`.
///
/// Use [ProfileSheet.show] in the real flow; [ProfileSheetPreview] renders it
/// full-screen (scrim + panel) for the debug gallery.
class ProfileSheet extends StatelessWidget {
  const ProfileSheet({super.key, this.onPick});
  final void Function(DemoProfile profile)? onPick;

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: const Color(0x6B14170F),
        builder: (_) => const ProfileSheet(),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
      decoration: const BoxDecoration(
        color: Cc.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0x2E202419),
                  borderRadius: BorderRadius.circular(99)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Who are we shopping for?',
              style: TextStyle(
                  fontFamily: 'Bricolage',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Cc.ink)),
          const SizedBox(height: 5),
          Text('Each profile has its own medications and ceilings.',
              style: CcText.body.copyWith(color: Cc.muted)),
          const SizedBox(height: 16),
          for (var i = 0; i < kProfiles.length; i++) ...[
            _ProfileRow(profile: kProfiles[i], onTap: () => onPick?.call(kProfiles[i])),
            if (i != kProfiles.length - 1) const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.profile, this.onTap});
  final DemoProfile profile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = profile.active;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active ? Cc.safeTint : Cc.paperRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: active ? const Color(0x5963753F) : const Color(0x14151510)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: active ? Cc.olive : const Color(0xFFEAEADB),
                  shape: BoxShape.circle),
              child: Text(profile.initial,
                  style: TextStyle(
                      fontFamily: 'Bricolage',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: active ? Cc.paper : Cc.oliveDark)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.name,
                      style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Cc.ink)),
                  const SizedBox(height: 2),
                  Text(profile.detail,
                      style: CcText.bodySm.copyWith(color: Cc.muted)),
                ],
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? Cc.olive : Colors.transparent,
                border: Border.all(
                    color: active ? Cc.olive : const Color(0x33202419), width: 2),
              ),
              child: active
                  ? const Icon(Icons.check_rounded, size: 11, color: Cc.paper)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrim + bottom-pinned panel. Used both for the debug preview and, in the
/// app shell, as the `state.showProfiles` overlay. Tapping the scrim calls
/// [onDismiss].
class ProfileSheetOverlay extends StatelessWidget {
  const ProfileSheetOverlay({super.key, this.onDismiss, this.onPick});
  final VoidCallback? onDismiss;
  final void Function(DemoProfile profile)? onPick;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ColoredBox(color: Color(0x6B14170F)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(child: ProfileSheet(onPick: onPick)),
        ),
      ],
    );
  }
}

/// Debug-gallery entry.
class ProfileSheetPreview extends StatelessWidget {
  const ProfileSheetPreview({super.key});

  @override
  Widget build(BuildContext context) => const ProfileSheetOverlay();
}
