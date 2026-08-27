// Verifies chipFor() score -> tone/colour mapping, and that the SeverityChip
// sample widget renders those colours. Boundary rule (from CareCart App.dc.html):
//   score >= 70 -> safe,  score >= 45 -> caution,  else avoid.

import 'package:carecart/src/core/severity.dart';
import 'package:carecart/src/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Case {
  const _Case(this.score, this.tone, this.color, this.tint);
  final num score;
  final Severity tone;
  final Color color;
  final Color tint;
}

const cases = <_Case>[
  // requested samples
  _Case(80, Severity.safe, Cc.safe, Cc.safeTint),
  _Case(50, Severity.caution, Cc.caution, Cc.cautionTint),
  _Case(20, Severity.avoid, Cc.avoid, Cc.avoidTint),
  // exact boundary values
  _Case(70, Severity.safe, Cc.safe, Cc.safeTint), // >= 70 is safe
  _Case(45, Severity.caution, Cc.caution, Cc.cautionTint), // >= 45 is caution
  // one below each boundary (off-by-one guard)
  _Case(69, Severity.caution, Cc.caution, Cc.cautionTint),
  _Case(44, Severity.avoid, Cc.avoid, Cc.avoidTint),
];

void main() {
  testWidgets('chipFor() returns the right tone + colour at each boundary, '
      'and SeverityChip renders them', (tester) async {
    for (final c in cases) {
      // --- unit: the function ---
      final s = chipFor(c.score);
      expect(s.tone, c.tone, reason: 'score ${c.score} tone');
      expect(s.color, c.color, reason: 'score ${c.score} color');
      expect(s.tint, c.tint, reason: 'score ${c.score} tint');

      // --- widget: the sample renders those colours ---
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: SeverityChip(c.score)))),
      );

      final box = tester.widget<Container>(find.byKey(const Key('severity-chip')));
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, c.tint, reason: 'score ${c.score} chip background');

      final text = tester.widget<Text>(find.text('${c.score.round()}'));
      expect(text.style!.color, c.color, reason: 'score ${c.score} chip text colour');

      // ignore: avoid_print
      print('score ${c.score.toString().padLeft(3)}  ->  ${c.tone.name.padRight(7)}  '
          'color=0x${c.color.toARGB32().toRadixString(16).toUpperCase()}  '
          'tint=0x${c.tint.toARGB32().toRadixString(16).toUpperCase()}   OK');
    }
  });
}
