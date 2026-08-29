import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'product_api.dart' show networkErrorMessage;

/// One row of the automatic diet log (Phase 5.1). Written server-side on every
/// `POST /scan/verdict`; there is no "log this" call.
class ScanHistoryEntry {
  const ScanHistoryEntry({
    required this.id,
    required this.productName,
    required this.score,
    required this.tier,
    required this.scannedAt,
    this.hardStop = false,
    this.keyReasons = const [],
  });

  final String id;
  final String productName;
  final int score;

  /// safe | caution | avoid
  final String tier;
  final bool hardStop;
  final List<HistoryReason> keyReasons;
  final DateTime scannedAt;

  factory ScanHistoryEntry.fromJson(Map<String, dynamic> j) => ScanHistoryEntry(
        id: j['id']?.toString() ?? '',
        productName: j['product_name'] as String? ?? '',
        score: (j['score'] as num?)?.toInt() ?? 0,
        tier: j['tier'] as String? ?? 'avoid',
        hardStop: j['hard_stop'] as bool? ?? false,
        keyReasons: (j['key_reasons'] as List?)
                ?.map((e) => HistoryReason.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        scannedAt: DateTime.tryParse(j['scanned_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class HistoryReason {
  const HistoryReason(
      {required this.kind, required this.severity, required this.title, this.factor});
  final String kind;
  final String severity;
  final String title;

  /// The recurring risk_compound this reason is about (Phase 5.3 grouping).
  final String? factor;

  factory HistoryReason.fromJson(Map<String, dynamic> j) => HistoryReason(
        kind: j['kind'] as String? ?? '',
        severity: j['severity'] as String? ?? 'info',
        title: j['title'] as String? ?? '',
        factor: j['factor'] as String?,
      );
}

class HistoryPage {
  const HistoryPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  final List<ScanHistoryEntry> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  factory HistoryPage.fromJson(Map<String, dynamic> j) => HistoryPage(
        items: (j['items'] as List?)
                ?.map((e) =>
                    ScanHistoryEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        total: (j['total'] as num?)?.toInt() ?? 0,
        limit: (j['limit'] as num?)?.toInt() ?? 0,
        offset: (j['offset'] as num?)?.toInt() ?? 0,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

sealed class HistoryResult {
  const HistoryResult();
}

class HistoryLoaded extends HistoryResult {
  const HistoryLoaded(this.page);
  final HistoryPage page;
}

class HistoryFailed extends HistoryResult {
  const HistoryFailed(this.message);
  final String message;
}

/// One `GET /api/v1/history?limit=&offset=`. Never throws. Most-recent-first.
Future<HistoryResult> fetchHistory(Dio dio,
    {int limit = 20, int offset = 0}) async {
  try {
    final res = await dio.get<Map<String, dynamic>>(
      '/history',
      queryParameters: {'limit': limit, 'offset': offset},
      options: Options(validateStatus: (s) => s != null),
    );
    final status = res.statusCode ?? 0;
    if (status == 200) {
      return HistoryLoaded(HistoryPage.fromJson(res.data ?? const {}));
    }
    return HistoryFailed(switch (status) {
      401 => 'Please sign in again.',
      _ => "Couldn't load your history ($status).",
    });
  } on DioException catch (e) {
    return HistoryFailed(
        networkErrorMessage(e, fallback: "Couldn't load your history."));
  }
}

/// Injectable — override in tests.
final historyProvider =
    Provider<Future<HistoryResult> Function({int limit, int offset})>(
  (ref) => ({int limit = 20, int offset = 0}) =>
      fetchHistory(ref.read(dioProvider), limit: limit, offset: offset),
);
