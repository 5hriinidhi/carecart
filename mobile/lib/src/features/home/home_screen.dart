import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

/// Placeholder home. Its only job right now is the Phase 1->2 integration
/// checkpoint: make one real HTTP call to the backend's `GET /health` and show
/// the result on screen, proving the client<->server wire is live.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthCheckProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('CareCart')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('backend: $apiBaseUrl/health',
                  style: const TextStyle(color: Cc.muted, fontSize: 12)),
              const SizedBox(height: 20),
              health.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => _StatusCard(
                  key: const Key('health-status'),
                  ok: false,
                  title: 'call failed',
                  detail: '$e',
                ),
                data: (r) => _StatusCard(
                  key: const Key('health-status'),
                  ok: r.reachable && r.dbConnected,
                  title: r.reachable
                      ? 'HTTP ${r.httpStatus} · status=${r.body['status']} · db=${r.body['db']}'
                      : 'unreachable',
                  detail: r.body.toString(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => ref.invalidate(healthCheckProvider),
                child: const Text('Ping backend /health'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    super.key,
    required this.ok,
    required this.title,
    required this.detail,
  });

  final bool ok;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final color = ok ? Cc.safe : Cc.avoid;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Cc.paperRaised,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ok ? Icons.check_circle : Icons.error_outline, color: color, size: 20),
              const SizedBox(width: 8),
              Text(ok ? 'wire is live' : 'no connection',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Cc.muted, fontSize: 11)),
        ],
      ),
    );
  }
}
