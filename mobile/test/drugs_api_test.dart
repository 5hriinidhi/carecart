// GET /drugs/search client — request shape, response parsing, error mapping.

import 'dart:convert';
import 'dart:typed_data';

import 'package:carecart/src/core/drugs_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);
  final ResponseBody Function(RequestOptions options) responder;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<void>? cancel) async {
    lastRequest = options;
    return responder(options);
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

const _body = {
  'query': 'ecospri',
  'results': [
    {
      'name': 'Ecosprin 75 Tablet',
      'salt_composition': 'Aspirin (75mg)',
      'active_ingredients': 'aspirin',
      'drug_classes': 'NSAID',
    },
    {
      'name': 'Ecosprin Gold 10 Capsule',
      'salt_composition': 'Aspirin (75mg) + Atorvastatin (10mg)',
      'active_ingredients': 'aspirin, atorvastatin',
      'drug_classes': 'NSAID, Statin',
    },
  ],
};

void main() {
  test('a short query never hits the network', () async {
    final adapter = _FakeAdapter((_) => throw StateError('should not be called'));
    final api = HttpDrugsApi(_dio(200, _body, adapter: adapter));

    final r = await api.search(' a ');
    expect(r, isA<DrugSearchHits>());
    expect((r as DrugSearchHits).hits, isEmpty);
    expect(adapter.lastRequest, isNull);
  });

  test('200 -> parsed hits, q + limit go on the query string', () async {
    final adapter = _FakeAdapter((_) => ResponseBody.fromString(
        jsonEncode(_body), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        }));
    final api = HttpDrugsApi(_dio(200, _body, adapter: adapter));

    final r = await api.search('  ecospri ', limit: 5);
    expect(r, isA<DrugSearchHits>());
    final hits = (r as DrugSearchHits).hits;
    expect(hits.map((h) => h.name),
        ['Ecosprin 75 Tablet', 'Ecosprin Gold 10 Capsule']);
    expect(hits.first.saltComposition, 'Aspirin (75mg)');
    expect(hits.first.subtitle, 'Aspirin (75mg)');
    expect(adapter.lastRequest!.uri.queryParameters['q'], 'ecospri');
    expect(adapter.lastRequest!.uri.queryParameters['limit'], '5');
  });

  test('401 -> a sign-in message', () async {
    final api = HttpDrugsApi(_dio(401, {'detail': 'nope'}));
    final r = await api.search('telma');
    expect(r, isA<DrugSearchError>());
    expect((r as DrugSearchError).message, contains('sign in'));
  });

  test('malformed rows are skipped, not fatal', () async {
    final api = HttpDrugsApi(_dio(200, {
      'results': [
        {'name': ''},
        {'name': 'Telma 40 Tablet', 'salt_composition': 'Telmisartan (40mg)'},
      ]
    }));
    final r = await api.search('telma') as DrugSearchHits;
    expect(r.hits.map((h) => h.name), ['Telma 40 Tablet']);
  });
}
