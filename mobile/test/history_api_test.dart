// GET /history client (Phase 5.1) — the automatic diet log, most-recent-first,
// paginated, this-user-only (scoping is enforced server-side).

import 'dart:convert';
import 'dart:typed_data';

import 'package:carecart/src/core/history_api.dart';
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

const _page = {
  'items': [
    {
      'id': 'b1',
      'product_name': 'Palak Sev',
      'score': 27,
      'tier': 'avoid',
      'hard_stop': false,
      'key_reasons': [
        {'kind': 'condition_ceiling', 'severity': 'high', 'title': 'High sodium for Hypertension'}
      ],
      'scanned_at': '2026-08-29T10:05:00Z',
    },
    {
      'id': 'a0',
      'product_name': 'Rolled Oats',
      'score': 100,
      'tier': 'safe',
      'hard_stop': false,
      'key_reasons': <Map<String, dynamic>>[],
      'scanned_at': '2026-08-29T09:00:00Z',
    },
  ],
  'total': 5,
  'limit': 2,
  'offset': 0,
  'has_more': true,
};

void main() {
  test('200 -> HistoryLoaded, newest first, fields parsed', () async {
    final r = await fetchHistory(_dio(200, _page));
    expect(r, isA<HistoryLoaded>());
    final p = (r as HistoryLoaded).page;
    expect(p.total, 5);
    expect(p.hasMore, isTrue);
    expect(p.items.map((e) => e.productName).toList(), ['Palak Sev', 'Rolled Oats']);
    expect(p.items.first.scannedAt.isAfter(p.items.last.scannedAt), isTrue);
    expect(p.items.first.tier, 'avoid');
    expect(p.items.first.keyReasons.single.title, 'High sodium for Hypertension');
    expect(p.items.last.keyReasons, isEmpty);
  });

  test('sends limit + offset as query params', () async {
    final a = _FakeAdapter((_) => ResponseBody.fromString(jsonEncode(_page), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        }));
    await fetchHistory(_dio(200, _page, adapter: a), limit: 10, offset: 20);
    expect(a.last!.uri.queryParameters['limit'], '10');
    expect(a.last!.uri.queryParameters['offset'], '20');
  });

  test('empty history -> loaded, no items', () {
    final p = HistoryPage.fromJson(const {
      'items': <Map<String, dynamic>>[],
      'total': 0,
      'limit': 20,
      'offset': 0,
      'has_more': false
    });
    expect(p.items, isEmpty);
    expect(p.hasMore, isFalse);
  });

  test('401 -> HistoryFailed(sign in), never throws', () async {
    final r = await fetchHistory(_dio(401, {'detail': 'x'}));
    expect((r as HistoryFailed).message, 'Please sign in again.');
  });

  test('connection error -> friendly message', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = _FakeAdapter((o) =>
        throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
    final r = await fetchHistory(dio);
    expect((r as HistoryFailed).message, 'No connection to the server.');
  });
}
