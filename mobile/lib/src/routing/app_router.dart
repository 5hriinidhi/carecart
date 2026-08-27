import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../debug/debug_gallery.dart';
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
      // /debug/* is exempt from the onboarding gate - it's a standalone
      // screen-preview area (Phase 2.2).
      if (state.matchedLocation.startsWith('/debug')) return null;

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
      GoRoute(
        path: '/debug',
        builder: (context, state) => DebugGalleryScreen(
          onOpen: (name) => context.go('/debug/$name'),
        ),
        routes: [
          GoRoute(
            path: ':name',
            builder: (context, state) => DebugScreenHost(
              name: state.pathParameters['name']!,
              onBack: () => context.go('/debug'),
            ),
          ),
        ],
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
