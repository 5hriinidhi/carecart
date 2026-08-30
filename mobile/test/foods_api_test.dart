// GET /foods/search client — request shape, response parsing, error mapping.

import 'dart:convert';
import 'dart:typed_data';

import 'package:carecart/src/core/foods_api.dart';
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
  'query': 'poha',
  'results': [
    {
      'name': 'Poha',
      'kind': 'dish',
      'ingredients_text': 'Flattened rice, peanuts, onion',
      'diet': 'vegetarian',
      'course': 'snack',
      'region': 'West',
      'nutriments': {},
    },
    {
      'name': 'MTR Poha Mix',
      'kind': 'packaged',
      'brand': 'MTR',
      'category': 'READY MIX',
      'serving_size': '80 g',
      'nutriments': {'energy_kcal_100g': 408.33, 'sugars_g_100g': 5.1},
    },
  ],
};

void main() {
  test('a short query never hits the network', () async {
    final adapter = _FakeAdapter((_) => throw StateError('no'));
    final api = HttpFoodsApi(_dio(200, _body, adapter: adapter));
    final r = await api.search('p');
    expect((r as FoodSearchHits).hits, isEmpty);
    expect(adapter.lastRequest, isNull);
  });

  test('200 -> parsed hits (dish + packaged), q/limit on the query string',
      () async {
    final adapter = _FakeAdapter((_) => ResponseBody.fromString(
        jsonEncode(_body), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        }));
    final api = HttpFoodsApi(_dio(200, _body, adapter: adapter));

    final hits = (await api.search(' poha ', limit: 8) as FoodSearchHits).hits;
    expect(hits.map((h) => h.name), ['Poha', 'MTR Poha Mix']);
    expect(hits[0].isPackaged, isFalse);
    expect(hits[0].subtitle, contains('snack'));
    expect(hits[1].isPackaged, isTrue);
    expect(hits[1].brand, 'MTR');
    expect(hits[1].nutriments['energy_kcal_100g'], 408.33);
    expect(adapter.lastRequest!.uri.queryParameters['q'], 'poha');
    expect(adapter.lastRequest!.uri.queryParameters['limit'], '8');
  });

  test('401 -> sign-in message', () async {
    final api = HttpFoodsApi(_dio(401, {'detail': 'x'}));
    final r = await api.search('poha');
    expect((r as FoodSearchError).message, contains('sign in'));
  });

  test('rows with a blank name are dropped', () async {
    final api = HttpFoodsApi(_dio(200, {
      'results': [
        {'name': '', 'kind': 'dish'},
        {'name': 'Dosa', 'kind': 'dish'},
      ]
    }));
    final r = await api.search('dosa') as FoodSearchHits;
    expect(r.hits.map((h) => h.name), ['Dosa']);
  });
}
