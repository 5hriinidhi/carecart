import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';

/// Flips to true once the 6-step profile build completes.
/// Wire this to real persistence (secure storage / API) later.
class OnboardingComplete extends Notifier<bool> {
  @override
  bool build() => false;

  void markDone() => state = true;
  void reset() => state = false;
}

final onboardingCompleteProvider =
    NotifierProvider<OnboardingComplete, bool>(OnboardingComplete.new);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final done = ref.read(onboardingCompleteProvider);
      final atOnboarding = state.matchedLocation.startsWith('/onboarding');
      if (!done && !atOnboarding) return '/onboarding';
      if (done && atOnboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
});

/// Bridges the Riverpod provider to go_router's Listenable-based refresh.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(onboardingCompleteProvider, (_, _) => notifyListeners());
  }
}
