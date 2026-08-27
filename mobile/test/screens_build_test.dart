// Every Phase 2.2 static screen must build and lay out without throwing,
// standalone (no navigation / providers / backend).

import 'package:carecart/src/debug/debug_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in debugScreens.entries) {
    testWidgets('screen "${entry.key}" builds standalone', (tester) async {
      tester.view.physicalSize = const Size(430, 908);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: entry.value.build)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull, reason: entry.value.label);
      // something actually rendered
      expect(find.byType(Scaffold), findsWidgets);
    });
  }
}
