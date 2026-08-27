import 'package:flutter/material.dart';

import 'severity.dart';
import 'text.dart';
import 'theme.dart';

/// Rounded-square score pill, tinted by [chipFor]. Matches `chipFor()` in the
/// prototype (38x38, radius 12).
class CcScoreChip extends StatelessWidget {
  const CcScoreChip(this.score, {super.key, this.size = 38});
  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = chipFor(score);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: s.tint, borderRadius: BorderRadius.circular(12)),
      child: Text('$score', style: CcText.chipNum(s.color)),
    );
  }
}

/// Thin capsule progress bar (7px) used on the result + condition screens.
class CcMeter extends StatelessWidget {
  const CcMeter({super.key, required this.pct, required this.color, this.height = 7});
  final int pct; // 0-100
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: height,
        color: const Color(0x14202419),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: (pct.clamp(2, 100)) / 100,
          child: Container(color: color),
        ),
      ),
    );
  }
}

/// Placeholder product thumbnail (the prototype uses a 135deg hatch).
class CcThumb extends StatelessWidget {
  const CcThumb({super.key, this.size = 42, this.radius = 11});
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x22202419), Color(0x08202419), Color(0x22202419)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

/// Bottom nav: Home · Trend · [scan FAB] · History · Meds.
/// Static - taps route to the matching debug screen.
class CcBottomNav extends StatelessWidget {
  const CcBottomNav({super.key, required this.active, this.onTapItem, this.onTapScan});
  final String active; // home | trends | history | meds
  final void Function(String route)? onTapItem;
  final VoidCallback? onTapScan;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, String route) {
      final on = route == active;
      return Expanded(
        child: GestureDetector(
          onTap: () => onTapItem?.call(route),
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Cc.safeTint : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 11.5,
                    fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                    color: on ? Cc.oliveDark : Cc.muted)),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Cc.paperRaised,
        border: Border(top: BorderSide(color: Color(0x14151510))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          item('Home', 'home'),
          item('Trend', 'trends'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: GestureDetector(
              onTap: onTapScan,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Cc.accent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Color(0x59D07E52), blurRadius: 16, offset: Offset(0, 6)),
                  ],
                ),
                child: const Icon(Icons.qr_code_scanner_rounded, color: Cc.inkSoft, size: 23),
              ),
            ),
          ),
          item('History', 'history'),
          item('Meds', 'meds'),
        ],
      ),
    );
  }
}

/// Small circular back / close button used in screen headers.
class CcRoundButton extends StatelessWidget {
  const CcRoundButton(
      {super.key,
      required this.icon,
      this.onTap,
      this.bg = const Color(0xFFEAEADB),
      this.fg = Cc.inkSoft,
      this.size = 38});
  final IconData icon;
  final VoidCallback? onTap;
  final Color bg;
  final Color fg;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.45, color: fg),
      ),
    );
  }
}

/// Section header row: title + optional trailing action text.
class CcSectionHead extends StatelessWidget {
  const CcSectionHead(this.title, {super.key, this.trailing, this.onTrailing});
  final String title;
  final String? trailing;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(title, style: CcText.h2)),
        if (trailing != null)
          GestureDetector(
            onTap: onTrailing,
            child: Text(trailing!,
                style: const TextStyle(
                    fontFamily: 'DMSans', fontSize: 12, fontWeight: FontWeight.w500, color: Cc.olive)),
          ),
      ],
    );
  }
}

/// A rounded pill chip (filter / range selectors).
class CcPill extends StatelessWidget {
  const CcPill(this.label, {super.key, this.active = false, this.onTap});
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Cc.inkSoft : Cc.paperRaised,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: active ? Cc.inkSoft : const Color(0x1A151510)),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: active ? Cc.paper : Cc.muted)),
      ),
    );
  }
}
