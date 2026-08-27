import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/theme.dart';

/// Phase 1->2 wire check, surfaced on the debug gallery: one real GET /health
/// and a pass/fail card. (Previously lived on HomeScreen.)
class HealthStatusTile extends ConsumerWidget {
  const HealthStatusTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthCheckProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('backend: $apiBaseUrl/health',
              style: const TextStyle(color: Cc.muted, fontSize: 12)),
          const SizedBox(height: 12),
          health.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => _card(ok: false, title: 'call failed', detail: '$e'),
            data: (r) => _card(
              ok: r.reachable && r.dbConnected,
              title: r.reachable
                  ? 'HTTP ${r.httpStatus} · status=${r.body['status']} · db=${r.body['db']}'
                  : 'unreachable',
              detail: r.body.toString(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => ref.invalidate(healthCheckProvider),
            child: const Text('Ping backend /health'),
          ),
        ],
      ),
    );
  }

  Widget _card({required bool ok, required String title, required String detail}) {
    final color = ok ? Cc.safe : Cc.avoid;
    return Container(
      key: const Key('health-status'),
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
