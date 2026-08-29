// GET /analytics/trends client (Phase 5.2).

import 'dart:convert';
import 'dart:typed_data';

import 'package:carecart/src/core/analytics_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);
  final ResponseBody Function(RequestOptions o) responder;
  RequestOptions? last;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    last = o;
    return responder(o);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(int status, Object body, {_FakeAdapter? adapter}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = adapter ??
      _FakeAdapter((_) => ResponseBody.fromString(jsonEncode(body), status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          }));
  return dio;
}

const _payload = {
  'timezone': 'Asia/Kolkata',
  'total_scans': 9,
  'diet_health_score': 63,
  'diet_health_score_delta_7d': 5,
  'trend': 'improving',
  'weekly': [
    {
      'period_start': '2026-08-03',
      'label': '3 Aug',
      'scans': 4,
      'avg_score': 55.0,
      'safe': 1,
      'caution': 2,
      'avoid': 1,
      'diet_health_score': 58,
    },
    {
      'period_start': '2026-08-10',
      'label': '10 Aug',
      'scans': 5,
      'avg_score': 68.0,
      'safe': 3,
      'caution': 2,
      'avoid': 0,
      'diet_health_score': 63,
    },
  ],
  'monthly': [
    {
      'period_start': '2026-08-01',
      'label': 'Aug 2026',
      'scans': 9,
      'avg_score': 62.2,
      'safe': 4,
      'caution': 4,
      'avoid': 1,
      'diet_health_score': 63,
    }
  ],
};

void main() {
  test('200 -> TrendsLoaded with score, trend, weekly + monthly buckets', () async {
    final r = await fetchTrends(_dio(200, _payload));
    expect(r, isA<TrendsLoaded>());
    final t = (r as TrendsLoaded).trends;
    expect(t.timezone, 'Asia/Kolkata');
    expect(t.totalScans, 9);
    expect(t.dietHealthScore, 63);
    expect(t.deltaSevenDay, 5);
    expect(t.trend, 'improving');
    expect(t.weekly.length, 2);
    expect(t.weekly.last.dietHealthScore, 63);
    expect(t.weekly.first.periodStart, DateTime(2026, 8, 3));
    expect(t.weekly.last.safe, 3);
    expect(t.monthly.single.label, 'Aug 2026');
    expect(t.isEmpty, isFalse);
  });

  test('sends the device UTC offset as tz_offset_minutes', () async {
    final a = _FakeAdapter((_) => ResponseBody.fromString(jsonEncode(_payload), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        }));
    await fetchTrends(_dio(200, _payload, adapter: a), tzOffsetMinutes: 330);
    expect(a.last!.uri.queryParameters['tz_offset_minutes'], '330');
  });

  test('empty history -> loaded + isEmpty', () async {
    final r = await fetchTrends(_dio(200, {
      'timezone': 'UTC',
      'total_scans': 0,
      'diet_health_score': 0,
      'diet_health_score_delta_7d': 0,
      'trend': 'steady',
      'weekly': <Map<String, dynamic>>[],
      'monthly': <Map<String, dynamic>>[],
    }));
    final t = (r as TrendsLoaded).trends;
    expect(t.isEmpty, isTrue);
    expect(t.weekly, isEmpty);
  });

  test('422 -> timezone message', () async {
    final r = await fetchTrends(_dio(422, {'detail': 'bad tz'}));
    expect((r as TrendsFailed).message, "Couldn't read your device timezone.");
  });

  test('401 -> sign in', () async {
    final r = await fetchTrends(_dio(401, {'detail': 'x'}));
    expect((r as TrendsFailed).message, 'Please sign in again.');
  });

  test('connection error -> friendly message, never throws', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = _FakeAdapter((o) =>
        throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
    final r = await fetchTrends(dio);
    expect((r as TrendsFailed).message, 'No connection to the server.');
  });

  // ---------------------------------------------------- outlier visibility
  test('parses median/min/max and flags a mean-skewed bucket', () async {
    final r = await fetchTrends(_dio(200, {
      ..._payload,
      'weekly': [
        {
          'period_start': '2026-08-03',
          'label': '3 Aug',
          'scans': 5,
          'avg_score': 73.8,
          'median_score': 90.0,
          'min_score': 8,
          'max_score': 92,
          'safe': 4,
          'caution': 0,
          'avoid': 1,
          'diet_health_score': 84,
        },
      ],
    }));
    final b = (r as TrendsLoaded).trends.weekly.single;
    expect(b.medianScore, 90.0);
    expect(b.minScore, 8);
    expect(b.maxScore, 92);
    expect(b.meanSkewed, isTrue); // |73.8 - 90| >= 10 and scans >= 3
  });

  test('a tight bucket is not flagged as skewed', () async {
    final r = await fetchTrends(_dio(200, {
      ..._payload,
      'weekly': [
        {
          'period_start': '2026-08-03',
          'label': '3 Aug',
          'scans': 4,
          'avg_score': 71.0,
          'median_score': 70.0,
          'min_score': 66,
          'max_score': 78,
          'safe': 3,
          'caution': 1,
          'avoid': 0,
          'diet_health_score': 72,
        },
      ],
    }));
    expect((r as TrendsLoaded).trends.weekly.single.meanSkewed, isFalse);
  });

  test('old payload without median fields still parses (no skew claimed)', () async {
    final r = await fetchTrends(_dio(200, _payload));
    final b = (r as TrendsLoaded).trends.weekly.first;
    expect(b.medianScore, b.avgScore); // falls back to the mean
    expect(b.meanSkewed, isFalse);
  });

  // ---------------------------------------------------- DST-correct tz name
  test('sends the IANA tz name when one is supplied', () async {
    final a = _FakeAdapter((_) => ResponseBody.fromString(jsonEncode(_payload), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        }));
    await fetchTrends(_dio(200, _payload, adapter: a),
        tzName: 'America/New_York', tzOffsetMinutes: -300);
    expect(a.last!.uri.queryParameters['tz'], 'America/New_York');
    expect(a.last!.uri.queryParameters['tz_offset_minutes'], '-300');
  });

  test('422 on an unknown tz name retries once with the numeric offset', () async {
    var calls = 0;
    final a = _FakeAdapter((o) {
      calls++;
      final hasName = o.uri.queryParameters.containsKey('tz');
      final body = hasName ? {'detail': 'Unknown timezone'} : _payload;
      return ResponseBody.fromString(jsonEncode(body), hasName ? 422 : 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
    });
    final r = await fetchTrends(_dio(200, _payload, adapter: a),
        tzName: 'Invalid/Zone', tzOffsetMinutes: -300);
    expect(calls, 2);
    expect(r, isA<TrendsLoaded>());
    expect(a.last!.uri.queryParameters.containsKey('tz'), isFalse);
  });

  test('deviceTimezoneName returns null under flutter test (no channel hang)',
      () async {
    expect(await deviceTimezoneName(), isNull);
  });
}
