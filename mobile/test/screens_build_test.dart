// Every Phase 2.2/2.3 static screen must build, lay out without throwing, AND
// actually render its content (a known headline string), standalone.

import 'package:carecart/src/debug/debug_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _signature = <String, String>{
  'home': 'Good evening',
  'scan': 'Hold the barcode in the frame',
  'analyzing': 'Setting up your verdict',
  'result': 'Avoid', // tier label from chipFor(score) — was the fixture's 'Not for you'
  'result-caution': 'Caution',
  'result-safe': 'Safe for you',
  'trends': 'Your trend',
  'history': 'Food history',
  'meds': 'Medications',
  'search': 'RECENTLY SCANNED NEAR YOU',
  'search-empty': 'Not in the database yet',
  'nudge': 'Sodium is creeping up on your weekday lunches',
  'profile-sheet': 'Who are we shopping for?',
};

void main() {
  for (final entry in debugScreens.entries) {
    testWidgets('screen "${entry.key}" builds and renders content', (tester) async {
      tester.view.physicalSize = const Size(430, 908);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Builder(builder: entry.value.build))),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull, reason: entry.value.label);

      final sig = _signature[entry.key];
      if (sig != null) {
        expect(find.textContaining(sig), findsWidgets,
            reason: '${entry.key}: screen content not rendered (expected "$sig")');
      }
    });
  }
}
