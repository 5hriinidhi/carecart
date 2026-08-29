import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the backend is currently reachable, inferred from the outcome of the
/// last few HTTP calls (Phase 6.3). This is more honest than OS-level
/// connectivity: the phone can be on Wi-Fi while the backend is down or the
/// captive portal is eating requests.
///
/// A `dioProvider` interceptor calls [Reachability.markOk] on any response and
/// [Reachability.markUnreachable] on a connection error / timeout. The UI reads
/// [isOffline] to switch banners between "offline — showing saved data" and a
/// hard failure.
enum Reach { unknown, online, offline }

class Reachability extends Notifier<Reach> {
  @override
  Reach build() => Reach.unknown;

  void markOk() {
    if (state != Reach.online) state = Reach.online;
  }

  void markUnreachable() {
    if (state != Reach.offline) state = Reach.offline;
  }
}

final reachabilityProvider =
    NotifierProvider<Reachability, Reach>(Reachability.new);

/// Convenience: true only once we've actually seen a failed call.
final isOfflineProvider =
    Provider<bool>((ref) => ref.watch(reachabilityProvider) == Reach.offline);
