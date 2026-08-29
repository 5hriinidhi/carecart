// GET /nudges + dismiss client (Phase 5.3).

import 'dart:convert';
import 'dart:typed_data';

import 'package:carecart/src/core/nudges_api.dart';
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
  'items': [
    {
      'id': 'n2',
      'seq': 2,
      'factor': 'sodium',
      'message': 'Sodium was flagged in 4 of your last 14 days of scans. Try a '
          'low-sodium namkeen and rinse canned pulses.',
      'hit_count': 4,
      'window_days': 14,
      'created_at': '2026-08-30T09:00:00Z',
      'dismissed_at': null,
    }
  ],
  'latest_seq': 2,
};

void main() {
  test('200 -> NudgesLoaded, fields parsed, actionable message intact', () async {
    final r = await fetchNudges(_dio(200, _payload));
    expect(r, isA<NudgesLoaded>());
    final p = (r as NudgesLoaded).page;
    expect(p.latestSeq, 2);
    final n = p.items.single;
    expect(n.factor, 'sodium');
    expect(n.hitCount, 4);
    expect(n.windowDays, 14);
    expect(n.dismissedAt, isNull);
    expect(n.message, contains('rinse canned pulses'));
  });

  test('sends since + include_dismissed query params', () async {
    final a = _FakeAdapter((_) => ResponseBody.fromString(jsonEncode(_payload), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        }));
    await fetchNudges(_dio(200, _payload, adapter: a),
        sinceSeq: 5, includeDismissed: true);
    expect(a.last!.uri.queryParameters['since'], '5');
    expect(a.last!.uri.queryParameters['include_dismissed'], 'true');
  });

  test('empty -> loaded, no items', () {
    final p = NudgesPage.fromJson(const {'items': <Map<String, dynamic>>[], 'latest_seq': 0});
    expect(p.items, isEmpty);
    expect(p.latestSeq, 0);
  });

  test('dismissNudge: 204 -> true, other -> false, never throws', () async {
    expect(await dismissNudge(_dio(204, {}), 'x'), isTrue);
    expect(await dismissNudge(_dio(404, {'detail': 'gone'}), 'x'), isFalse);
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = _FakeAdapter((o) => throw DioException(
        requestOptions: o, type: DioExceptionType.connectionError));
    expect(await dismissNudge(dio, 'x'), isFalse);
  });

  test('401 -> NudgesFailed, connection error -> friendly', () async {
    expect((await fetchNudges(_dio(401, {'d': 'x'})) as NudgesFailed).message,
        'Please sign in again.');
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = _FakeAdapter((o) => throw DioException(
        requestOptions: o, type: DioExceptionType.connectionError));
    expect((await fetchNudges(dio) as NudgesFailed).message,
        'No connection to the server.');
  });
}
