import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'product_api.dart' show networkErrorMessage;

/// A behavioural nudge (Phase 5.3) — generated server-side after a scan when a
/// risk factor keeps recurring. `message` is a specific, actionable suggestion.
class Nudge {
  const Nudge({
    required this.id,
    required this.seq,
    required this.factor,
    required this.message,
    required this.hitCount,
    required this.windowDays,
    required this.createdAt,
    this.dismissedAt,
  });

  final String id;
  final int seq;
  final String factor; // the recurring risk_compound (sodium, added_sugar, …)
  final String message;
  final int hitCount;
  final int windowDays;
  final DateTime createdAt;
  final DateTime? dismissedAt;

  factory Nudge.fromJson(Map<String, dynamic> j) => Nudge(
        id: j['id']?.toString() ?? '',
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        factor: j['factor'] as String? ?? '',
        message: j['message'] as String? ?? '',
        hitCount: (j['hit_count'] as num?)?.toInt() ?? 0,
        windowDays: (j['window_days'] as num?)?.toInt() ?? 14,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        dismissedAt: (j['dismissed_at'] as String?) == null
            ? null
            : DateTime.tryParse(j['dismissed_at'] as String),
      );
}

class NudgesPage {
  const NudgesPage({required this.items, required this.latestSeq});
  final List<Nudge> items;
  final int latestSeq;

  factory NudgesPage.fromJson(Map<String, dynamic> j) => NudgesPage(
        items: (j['items'] as List?)
                ?.map((e) => Nudge.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        latestSeq: (j['latest_seq'] as num?)?.toInt() ?? 0,
      );
}

sealed class NudgesResult {
  const NudgesResult();
}

class NudgesLoaded extends NudgesResult {
  const NudgesLoaded(this.page);
  final NudgesPage page;
}

class NudgesFailed extends NudgesResult {
  const NudgesFailed(this.message);
  final String message;
}

/// `GET /api/v1/nudges?since=&include_dismissed=`. Never throws.
Future<NudgesResult> fetchNudges(Dio dio,
    {int sinceSeq = 0, bool includeDismissed = false}) async {
  try {
    final res = await dio.get<Map<String, dynamic>>(
      '/nudges',
      queryParameters: {
        'since': sinceSeq,
        if (includeDismissed) 'include_dismissed': true,
      },
      options: Options(validateStatus: (s) => s != null),
    );
    final status = res.statusCode ?? 0;
    if (status == 200) {
      return NudgesLoaded(NudgesPage.fromJson(res.data ?? const {}));
    }
    return NudgesFailed(status == 401
        ? 'Please sign in again.'
        : "Couldn't load your nudges ($status).");
  } on DioException catch (e) {
    return NudgesFailed(
        networkErrorMessage(e, fallback: "Couldn't load your nudges."));
  }
}

/// `POST /api/v1/nudges/{id}/dismiss`. Returns true on success (204 / already
/// dismissed). Never throws.
Future<bool> dismissNudge(Dio dio, String id) async {
  try {
    final res = await dio.post<void>(
      '/nudges/$id/dismiss',
      options: Options(validateStatus: (s) => s != null),
    );
    return res.statusCode == 204;
  } on DioException {
    return false;
  }
}

/// Drives the nudge screen + the post-scan poll. Auto-disposes so it refetches
/// on reopen.
final nudgesProvider = FutureProvider.autoDispose<NudgesResult>(
  (ref) => fetchNudges(ref.read(dioProvider)),
);
