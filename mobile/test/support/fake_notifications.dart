import 'package:carecart/src/core/notifications.dart';

/// Records calls; permission is whatever you set. Used to prove the nudge wiring
/// without touching platform channels.
class FakeNotificationService implements NotificationService {
  FakeNotificationService({this.granted = false});

  bool granted;
  int permissionRequests = 0;
  final List<({String title, String body})> shown = [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<void> showNudge({required String title, required String body}) async {
    if (!granted) return; // mirror the real service's "never assume" guard
    shown.add((title: title, body: body));
  }
}
