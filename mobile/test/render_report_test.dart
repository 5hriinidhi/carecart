// Instrumented render pass over every Phase 2.2 debug screen.
// For each screen, at two widths (430 and a tight 360):
//   - scrolls the whole screen top->bottom so every row is built
//   - flags any layout exception (RenderFlex overflow etc.) at any scroll pos
//   - checks every CcScoreChip's rendered colours against chipFor()/theme
//   - reports background colours painted + ellipsis-guarded Text count
//
//   flutter test test/render_report_test.dart -r expanded

import 'package:carecart/src/core/severity.dart';
import 'package:carecart/src/core/widgets.dart';
import 'package:carecart/src/debug/debug_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(Color c) {
  final v = c.toARGB32();
  final rgb = (v & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0');
  final a = (v >> 24) & 0xFF;
  return a == 0xFF ? '#$rgb' : '#$rgb/a$a';
}

Future<Object?> _scrollThrough(WidgetTester tester) async {
  Object? firstError;
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isEmpty) {
    return tester.takeException();
  }
  for (var i = 0; i < 14; i++) {
    final e = tester.takeException();
    firstError ??= e;
    await tester.drag(scrollable.first, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 60));
  }
  final e = tester.takeException();
  firstError ??= e;
  return firstError;
}

void main() {
  for (final entry in debugScreens.entries) {
    for (final width in const [430.0, 360.0]) {
      testWidgets('render: ${entry.key} @ ${width.toInt()}w', (tester) async {
        tester.view.physicalSize = Size(width, 908);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
            MaterialApp(home: Scaffold(body: Builder(builder: entry.value.build))));
        await tester.pump(const Duration(milliseconds: 300));

        final err = await _scrollThrough(tester);

        final buf = StringBuffer('\n─── /debug/${entry.key} @ ${width.toInt()}w  (${entry.value.label})\n');
        buf.writeln(err == null ? 'layout exceptions : NONE' : 'layout exceptions : !!! $err');

        final bgs = <String>{};
        for (final w in tester.allWidgets) {
          if (w is Scaffold && w.backgroundColor != null) {
            bgs.add('scaffold=${_hex(w.backgroundColor!)}');
          }
          if (w is Container) {
            if (w.color != null) bgs.add(_hex(w.color!));
            final d = w.decoration;
            if (d is BoxDecoration && d.color != null) bgs.add(_hex(d.color!));
          }
        }
        buf.writeln('bg colours        : ${bgs.take(14).join(", ")}');

        final chips = tester.widgetList<CcScoreChip>(find.byType(CcScoreChip)).toList();
        if (chips.isEmpty) {
          buf.writeln('severity chips    : (none built in viewport path)');
        } else {
          var allOk = true;
          final seen = <int>{};
          for (final chip in chips) {
            if (!seen.add(chip.score)) continue;
            final want = chipFor(chip.score);
            final f = find.byWidget(chip);
            final box = tester.widget<Container>(
                find.descendant(of: f, matching: find.byType(Container)).first);
            final gotTint = (box.decoration as BoxDecoration).color;
            final gotFg = tester
                .widget<Text>(find.descendant(of: f, matching: find.byType(Text)).first)
                .style
                ?.color;
            final ok = gotTint == want.tint && gotFg == want.color;
            allOk &= ok;
            buf.writeln('  ${chip.score.toString().padLeft(3)} -> ${want.tone.name.padRight(7)} '
                'tint ${_hex(gotTint!)}  fg ${_hex(gotFg!)}  ${ok ? "MATCH theme" : "MISMATCH"}');
          }
          buf.writeln('severity chips    : ${allOk ? "all match chipFor()/theme" : "MISMATCH ABOVE"}');
        }

        final ell = tester.allWidgets.whereType<Text>().where((t) => t.overflow == TextOverflow.ellipsis).length;
        buf.writeln('ellipsis-guarded Text: $ell');

        // ignore: avoid_print
        print(buf.toString());
        expect(err, isNull, reason: '${entry.key} @ ${width.toInt()}w threw a layout exception');
      });
    }
  }
}
