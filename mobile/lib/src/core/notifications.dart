import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local push for nudges (Phase 5.3).
///
/// Permission is **never assumed granted**. Nothing is shown until the user has
/// explicitly accepted via [requestPermission] (wired to the nudge screen's
/// "Remind me" button); [showNudge] itself re-checks and no-ops if not granted.
abstract class NotificationService {
  Future<void> init();

  /// Current OS permission state — does NOT prompt.
  Future<bool> isGranted();

  /// Explicitly ask the OS. Returns whether it is now granted.
  Future<bool> requestPermission();

  /// Show a nudge notification. Silently does nothing unless [isGranted].
  Future<void> showNudge({required String title, required String body});
}

/// A no-op service — the default in tests and on unsupported platforms.
class NoopNotificationService implements NotificationService {
  const NoopNotificationService();
  @override
  Future<void> init() async {}
  @override
  Future<bool> isGranted() async => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> showNudge({required String title, required String body}) async {}
}

class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;
  bool _unavailable = false; // plugin channel missing (e.g. under flutter test)
  bool _granted = false;

  static const _channelId = 'carecart_nudges';

  @override
  Future<void> init() async {
    if (_initialised || _unavailable) return;
    try {
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // do NOT request on init — permission is asked explicitly later
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ));
      _initialised = true;
    } catch (_) {
      _unavailable = true; // no platform side available; every call no-ops
    }
  }

  @override
  Future<bool> isGranted() async {
    if (kIsWeb) return false;
    await init();
    if (_unavailable) return false;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      _granted = await android?.areNotificationsEnabled() ?? false;
    } else if (Platform.isIOS) {
      // iOS has no non-prompting getter in this plugin version; trust the last
      // requestPermission() outcome.
    }
    return _granted;
  }

  @override
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    await init();
    if (_unavailable) return false;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      _granted = await android?.requestNotificationsPermission() ?? false;
    } else if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      _granted = await ios?.requestPermissions(
              alert: true, badge: true, sound: true) ??
          false;
    }
    return _granted;
  }

  @override
  Future<void> showNudge({required String title, required String body}) async {
    if (!await isGranted()) return; // defence in depth — never assume
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Nudges',
          channelDescription: 'Behavioural nudges from CareCart',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}

/// Injectable — a real service in the app, overridden with a fake in tests.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  if (kIsWeb) return const NoopNotificationService();
  return LocalNotificationService();
});
