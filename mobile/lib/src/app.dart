import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'routing/app_router.dart';

class CareCartApp extends ConsumerWidget {
  const CareCartApp({super.key});

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
