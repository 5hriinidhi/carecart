// Notification service (Phase 5.3) — permission is NEVER assumed granted.

import 'package:carecart/src/core/notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notifications.dart';

void main() {
  test('NoopNotificationService never grants and never shows', () async {
    const s = NoopNotificationService();
    expect(await s.isGranted(), isFalse);
    expect(await s.requestPermission(), isFalse);
    await s.showNudge(title: 't', body: 'b'); // completes, no-op
  });

  test('LocalNotificationService is inert without a platform channel (test env)',
      () async {
    final s = LocalNotificationService();
    // no plugin channel under `flutter test` -> everything reports "not granted"
    expect(await s.isGranted(), isFalse);
    expect(await s.requestPermission(), isFalse);
    await s.showNudge(title: 't', body: 'b'); // must NOT throw
  });

  test('showNudge only fires after an explicit grant', () async {
    final denied = FakeNotificationService(granted: false);
    await denied.showNudge(title: 't', body: 'b');
    expect(denied.shown, isEmpty);

    final granted = FakeNotificationService(granted: true);
    expect(granted.permissionRequests, 0);
    await granted.requestPermission();
    expect(granted.permissionRequests, 1); // explicit ask
    await granted.showNudge(title: 'A pattern', body: 'cut the sodium');
    expect(granted.shown.single.body, 'cut the sodium');
  });

  test('permission revoked at the OS level after a grant -> showNudge goes quiet',
      () async {
    final s = FakeNotificationService(granted: true);
    await s.showNudge(title: 'A pattern', body: 'first');
    expect(s.shown.length, 1);

    // user turns CareCart notifications off in system settings
    s.granted = false;

    await s.showNudge(title: 'A pattern', body: 'second');
    expect(s.shown.length, 1, reason: 'no delivery once the OS revokes it');
    // and it is re-checked every call, not cached from the earlier grant
    expect(await s.isGranted(), isFalse);
  });
}
