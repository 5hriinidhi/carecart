import 'package:flutter/material.dart';

import 'theme.dart';

/// The three verdict tones from the CareCart prototype.
enum Severity { avoid, caution, safe }

/// Colours + label for one [Severity], matching `SEV{}` in `CareCart App.dc.html`.
@immutable
class SeverityStyle {
  const SeverityStyle(this.tone, this.color, this.tint, this.label);

  final Severity tone;
  final Color color; // foreground / accent
  final Color tint; // background
  final String label;
}

const SeverityStyle _avoid =
    SeverityStyle(Severity.avoid, Cc.avoid, Cc.avoidTint, 'Avoid');
const SeverityStyle _caution =
    SeverityStyle(Severity.caution, Cc.caution, Cc.cautionTint, 'Caution');
const SeverityStyle _safe =
    SeverityStyle(Severity.safe, Cc.safe, Cc.safeTint, 'Safe for you');

/// Maps a 0-100 CareCart score to its severity tone.
///
/// Mirrors `chipFor()` in `CareCart App.dc.html`:
///   score >= 70 -> safe,  score >= 45 -> caution,  else avoid.
SeverityStyle chipFor(num score) {
  if (score >= 70) return _safe;
  if (score >= 45) return _caution;
  return _avoid;
}

/// Small sample widget: a score pill tinted by [chipFor].
class SeverityChip extends StatelessWidget {
  const SeverityChip(this.score, {super.key});

  final num score;

  @override
  Widget build(BuildContext context) {
    final s = chipFor(score);
    return Container(
      key: const Key('severity-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: s.tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${score.round()}',
        style: TextStyle(color: s.color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
