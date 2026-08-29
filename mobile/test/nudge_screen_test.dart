// Nudge screen (Phase 5.3) wired to GET /nudges.

import 'package:carecart/src/core/notifications.dart';
import 'package:carecart/src/core/nudges_api.dart';
import 'package:carecart/src/core/theme.dart';
import 'package:carecart/src/features/nudge/nudge_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notifications.dart';

Nudge _n({String factor = 'sodium'}) => Nudge(
      id: 'n1',
      seq: 1,
      factor: factor,
      hitCount: 4,
      windowDays: 14,
      createdAt: DateTime(2026, 8, 20),
      message: 'Sodium was flagged in 4 of your last 14 days of scans. Try a '
          'low-sodium namkeen and rinse canned pulses.',
    );

Widget _app(
  NudgesResult nudges, {
  NotificationService? notifs,
  VoidCallback? onHome,
}) =>
    ProviderScope(
      overrides: [
        nudgesProvider.overrideWith((ref) async => nudges),
        if (notifs != null)
          notificationServiceProvider.overrideWithValue(notifs),
      ],
      child: MaterialApp(
        theme: buildCareCartTheme(),
        home: Scaffold(body: NudgeScreen(onHome: onHome)),
      ),
    );

void main() {
  testWidgets('renders the newest nudge: heading + actionable message', (tester) async {
    await tester.pumpWidget(
        _app(NudgesLoaded(NudgesPage(items: [_n()], latestSeq: 1))));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('nudge-heading'))).data,
        'Sodium keeps turning up in your scans');
    expect(find.text('ONE CHANGE TO TRY'), findsOneWidget);
    expect(find.textContaining('rinse canned pulses'), findsOneWidget);
  });

  testWidgets('empty -> "Nothing to flag right now"', (tester) async {
    await tester.pumpWidget(
        _app(const NudgesLoaded(NudgesPage(items: [], latestSeq: 0))));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to flag right now'), findsOneWidget);
    expect(find.byKey(const Key('nudge-heading')), findsNothing);
  });

  testWidgets('Remind me: asks permission explicitly; on grant it shows + notes done',
      (tester) async {
    final notifs = FakeNotificationService(granted: true);
    await tester.pumpWidget(
        _app(NudgesLoaded(NudgesPage(items: [_n()], latestSeq: 1)), notifs: notifs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remind me'));
    await tester.pumpAndSettle();

    expect(notifs.permissionRequests, 1);
    expect(notifs.shown.single.body, contains('rinse canned pulses'));
    expect(tester.widget<Text>(find.byKey(const Key('nudge-note'))).data,
        contains("we'll nudge you"));
  });

  testWidgets(
      'Remind me: on denial nothing is shown, a settings hint appears, and it '
      'does NOT re-prompt on repeated taps', (tester) async {
    final notifs = FakeNotificationService(granted: false);
    await tester.pumpWidget(
        _app(NudgesLoaded(NudgesPage(items: [_n()], latestSeq: 1)), notifs: notifs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remind me'));
    await tester.pumpAndSettle();

    expect(notifs.permissionRequests, 1); // asked exactly once
    expect(notifs.shown, isEmpty);        // nothing shown without a grant
    expect(tester.widget<Text>(find.byKey(const Key('nudge-note'))).data,
        contains('Notifications are off'));
    // the button relabels so it no longer reads as a prompt
    expect(find.text('Remind me'), findsNothing);
    expect(find.text('Notifications off'), findsOneWidget);

    // hammer it — no crash, no fresh OS prompts
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Notifications off'));
      await tester.pumpAndSettle();
    }
    expect(notifs.permissionRequests, 1); // STILL one — never re-prompts
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.byKey(const Key('nudge-note'))).data,
        contains('Settings'));
  });

  testWidgets('Not now -> returns home', (tester) async {
    var wentHome = false;
    await tester.pumpWidget(_app(
      NudgesLoaded(NudgesPage(items: [_n()], latestSeq: 1)),
      notifs: FakeNotificationService(),
      onHome: () => wentHome = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(wentHome, isTrue);
  });
}
