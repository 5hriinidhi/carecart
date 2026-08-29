import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth_repository.dart';
import 'core/theme.dart';
import 'routing/app_router.dart';

class CareCartApp extends ConsumerWidget {
  const CareCartApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One-shot startup: restore a stored session (if any) before we decide
    // whether to show onboarding or drop straight into the app.
    final boot = ref.watch(authBootstrapProvider);

    return boot.when(
      loading: () => const _Splash(),
      error: (_, _) => const _RoutedApp(),
      data: (hasSession) {
        if (hasSession) {
          // a token was restored — skip onboarding on this launch.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(onboardingCompleteProvider.notifier).markDone();
          });
        }
        return const _RoutedApp();
      },
    );
  }
}

class _RoutedApp extends ConsumerWidget {
  const _RoutedApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'CareCart',
      debugShowCheckedModeBanner: false,
      theme: buildCareCartTheme(),
      routerConfig: router,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCareCartTheme(),
      home: const Scaffold(
        backgroundColor: Cc.paper,
        body: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2, color: Cc.olive),
          ),
        ),
      ),
    );
  }
}
