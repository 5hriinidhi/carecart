import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Placeholder home. Calls GET /api/v1/health to prove the app <-> API wiring.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _status = 'not checked';

  Future<void> _ping() async {
    setState(() => _status = 'checking...');
    try {
      final res = await ref.read(dioProvider).get<Map<String, dynamic>>('/health');
      setState(() => _status = 'API says: ${res.data}');
    } catch (e) {
      setState(() => _status = 'API unreachable: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CareCart')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _ping, child: const Text('Ping backend /health')),
          ],
        ),
      ),
    );
  }
}
