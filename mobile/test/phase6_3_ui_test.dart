// Phase 6.3 — the offline / cached UI states and the manual-barcode client
// validation.

import 'package:carecart/src/core/connectivity.dart';
import 'package:carecart/src/core/history_api.dart';
import 'package:carecart/src/core/theme.dart';
import 'package:carecart/src/features/history/history_screen.dart';
import 'package:carecart/src/features/scan/scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ScanHistoryEntry _h(String name, String tier) => ScanHistoryEntry(
      id: name,
      productName: name,
      score: tier == 'safe' ? 92 : 40,
      tier: tier,
      scannedAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
    );

void main() {
  testWidgets('history screen shows the "offline — saved history" banner over '
      'real rows (not a hard error)', (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        historyPageProvider.overrideWith((ref) async => HistoryOffline(
              [_h('Sea-Salt Crackers', 'caution'), _h('Rolled Oats', 'safe')],
              DateTime.now().subtract(const Duration(minutes: 12)),
            )),
      ],
      child: const MaterialApp(home: Scaffold(body: HistoryScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history-offline-banner')), findsOneWidget);
    expect(find.textContaining('Offline'), findsWidgets);
    expect(find.text('Sea-Salt Crackers'), findsOneWidget);
    expect(find.text('Rolled Oats'), findsOneWidget);
    // it is NOT the bare failure text
    expect(find.textContaining("Couldn't load your history"), findsNothing);
  });

  testWidgets('history hard failure (no cache) shows the plain error', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        historyPageProvider.overrideWith(
            (ref) async => const HistoryFailed('No connection to the server.')),
      ],
      child: const MaterialApp(home: Scaffold(body: HistoryScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-offline-banner')), findsNothing);
    expect(find.text('No connection to the server.'), findsOneWidget);
  });

  testWidgets('manual barcode field blocks a too-short code client-side',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final submitted = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildCareCartTheme(),
      home: Scaffold(
        body: ScanScreen(cameraEnabled: false, onBarcode: submitted.add),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('scan-barcode-field')), '123');
    await tester.tap(find.byKey(const Key('scan-barcode-submit')));
    await tester.pump();
    expect(find.byKey(const Key('scan-barcode-error')), findsOneWidget);
    expect(submitted, isEmpty, reason: 'bad input must not fire a lookup');

    await tester.enterText(
        find.byKey(const Key('scan-barcode-field')), '8901234567890');
    await tester.pump();
    expect(find.byKey(const Key('scan-barcode-error')), findsNothing,
        reason: 'error clears as the user fixes it');
    await tester.tap(find.byKey(const Key('scan-barcode-submit')));
    await tester.pump();
    expect(submitted, ['8901234567890']);
  });

  testWidgets('manual barcode field strips non-digits as you type', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final submitted = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScanScreen(cameraEnabled: false, onBarcode: submitted.add),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('scan-barcode-field')), '890-abc-123-4567xy');
    await tester.tap(find.byKey(const Key('scan-barcode-submit')));
    await tester.pump();
    expect(submitted, ['8901234567']); // only the digits, capped at 14
  });

  test('isOffline is only true after a failed call is seen', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(isOfflineProvider), isFalse); // unknown != offline
    c.read(reachabilityProvider.notifier).markUnreachable();
    expect(c.read(isOfflineProvider), isTrue);
  });
}
