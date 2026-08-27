import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../routing/app_router.dart';

/// Placeholder for the sign-in -> OTP -> 6 profile steps -> profile-build flow
/// (see turn 2a in `CareCart App.dc.html`).
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('CareCart', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text("Know what's in the pack before it goes in the trolley.",
                style: TextStyle(color: Cc.muted)),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => ref.read(onboardingCompleteProvider.notifier).markDone(),
              child: const Text('Skip onboarding (stub)'),
            ),
          ],
        ),
      ),
    );
  }
}
