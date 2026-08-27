import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../debug/debug_gallery.dart';
import '../features/app_shell.dart';
import '../features/onboarding/onboarding_screen.dart';

/// Onboarding gate. SEPARATE from the main-app state machine ([mainAppProvider])
/// - do not merge or cross-reference the two (CLAUDE.md).
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
      final loc = state.matchedLocation;

      // /debug/* is a standalone screen-preview area, exempt from the gate.
      if (loc.startsWith('/debug')) return null;

      final done = ref.read(onboardingCompleteProvider);
      final atOnboarding = loc.startsWith('/onboarding');

      if (!done) return atOnboarding ? null : '/onboarding';
      // onboarding complete -> land in the app
      if (atOnboarding || loc == '/') return '/app';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/app',
        builder: (context, state) => const MainAppShell(),
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
