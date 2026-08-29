import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'product_api.dart' show networkErrorMessage;

/// One weekly or monthly bucket from `GET /analytics/trends` (Phase 5.2).
class TrendBucket {
  const TrendBucket({
    required this.periodStart,
    required this.label,
    required this.scans,
    required this.avgScore,
    required this.safe,
    required this.caution,
    required this.avoid,
    required this.dietHealthScore,
  });

  final DateTime periodStart;
  final String label;
  final int scans;
  final double avgScore;
  final int safe;
  final int caution;
  final int avoid;

  /// Rolling Diet Health Score as of the last scan in this bucket.
  final int dietHealthScore;

  factory TrendBucket.fromJson(Map<String, dynamic> j) => TrendBucket(
        periodStart: DateTime.tryParse(j['period_start'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        label: j['label'] as String? ?? '',
        scans: (j['scans'] as num?)?.toInt() ?? 0,
        avgScore: (j['avg_score'] as num?)?.toDouble() ?? 0,
        safe: (j['safe'] as num?)?.toInt() ?? 0,
        caution: (j['caution'] as num?)?.toInt() ?? 0,
        avoid: (j['avoid'] as num?)?.toInt() ?? 0,
        dietHealthScore: (j['diet_health_score'] as num?)?.toInt() ?? 0,
      );
}

class Trends {
  const Trends({
    required this.timezone,
    required this.totalScans,
    required this.dietHealthScore,
    required this.deltaSevenDay,
    required this.trend,
    this.weekly = const [],
    this.monthly = const [],
  });

  final String timezone;
  final int totalScans;
  final int dietHealthScore;
  final int deltaSevenDay;

  /// improving | declining | steady
  final String trend;
  final List<TrendBucket> weekly;
  final List<TrendBucket> monthly;

  bool get isEmpty => totalScans == 0;

  factory Trends.fromJson(Map<String, dynamic> j) => Trends(
        timezone: j['timezone'] as String? ?? 'UTC',
        totalScans: (j['total_scans'] as num?)?.toInt() ?? 0,
        dietHealthScore: (j['diet_health_score'] as num?)?.toInt() ?? 0,
        deltaSevenDay: (j['diet_health_score_delta_7d'] as num?)?.toInt() ?? 0,
        trend: j['trend'] as String? ?? 'steady',
        weekly: (j['weekly'] as List?)
                ?.map((e) => TrendBucket.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        monthly: (j['monthly'] as List?)
                ?.map((e) => TrendBucket.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

sealed class TrendsResult {
  const TrendsResult();
}

class TrendsLoaded extends TrendsResult {
  const TrendsLoaded(this.trends);
  final Trends trends;
}

class TrendsFailed extends TrendsResult {
  const TrendsFailed(this.message);
  final String message;
}

/// One `GET /api/v1/analytics/trends`. Passes the device's current UTC offset so
/// the server buckets weeks on the user's local midnight. Never throws.
Future<TrendsResult> fetchTrends(Dio dio, {int? tzOffsetMinutes}) async {
  try {
    final res = await dio.get<Map<String, dynamic>>(
      '/analytics/trends',
      queryParameters: {'tz_offset_minutes': ?tzOffsetMinutes},
      options: Options(validateStatus: (s) => s != null),
    );
    final status = res.statusCode ?? 0;
    if (status == 200) {
      return TrendsLoaded(Trends.fromJson(res.data ?? const {}));
    }
    return TrendsFailed(switch (status) {
      401 => 'Please sign in again.',
      422 => "Couldn't read your device timezone.",
      _ => "Couldn't load your trends ($status).",
    });
  } on DioException catch (e) {
    return TrendsFailed(
        networkErrorMessage(e, fallback: "Couldn't load your trends."));
  }
}

/// Drives the trends screen. Auto-disposes so it refetches when the screen is
/// reopened (e.g. after a scan added history).
final trendsProvider = FutureProvider.autoDispose<TrendsResult>((ref) {
  final offset = DateTime.now().timeZoneOffset.inMinutes;
  return fetchTrends(ref.read(dioProvider), tzOffsetMinutes: offset);
});
