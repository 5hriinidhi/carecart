// GET /products/{barcode} client (Phase 4.1): parsing every outcome + auth header.

import 'dart:convert';
import 'dart:typed_data';

import 'package:carecart/src/core/api_client.dart';
import 'package:carecart/src/core/product_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);
  final ResponseBody Function(RequestOptions options) responder;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioReturning(int status, Object body, {_FakeAdapter? adapter}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = adapter ??
      _FakeAdapter((_) => ResponseBody.fromString(
            jsonEncode(body),
            status,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            },
          ));
  return dio;
}

const _productJson = {
  'barcode': '3017620422003',
  'name': 'Nutella',
  'brand': 'Ferrero',
  'ingredients': ['Sugar', 'Palm oil', 'Hazelnuts'],
  'ingredients_text': 'Sugar, palm oil, hazelnuts',
  'nutriments': {'sugars_g_100g': 56.3, 'sodium_mg_100g': 42.8},
  'serving_size': '15 g',
  'image_url': 'https://img/front.jpg',
  'source': 'openfoodfacts',
  'refreshed_at': '2026-08-28T00:00:00Z',
  'cached': true,
  'stale': false,
};

void main() {
  test('200 -> ProductFound with normalised fields', () async {
    final r = await lookupProduct(_dioReturning(200, _productJson), '3017620422003');
    expect(r, isA<ProductFound>());
    final p = (r as ProductFound).product;
    expect(p.name, 'Nutella');
    expect(p.brand, 'Ferrero');
    expect(p.ingredients, ['Sugar', 'Palm oil', 'Hazelnuts']);
    expect(p.nutriments['sodium_mg_100g'], 42.8);
    expect(p.servingSize, '15 g');
    expect(p.cached, isTrue);
    expect(p.stale, isFalse);
  });

  test('404 with fallback:ocr -> ProductNotFound(fallbackToOcr: true)', () async {
    final r = await lookupProduct(
      _dioReturning(404, {
        'detail': 'not in the database',
        'barcode': '0000000000000',
        'fallback': 'ocr',
      }),
      '0000000000000',
    );
    expect(r, isA<ProductNotFound>());
    expect((r as ProductNotFound).fallbackToOcr, isTrue);
    expect(r.barcode, '0000000000000');
  });

  test('404 without an ocr flag -> fallbackToOcr false', () async {
    final r = await lookupProduct(_dioReturning(404, {'detail': 'gone'}), '123456789012');
    expect((r as ProductNotFound).fallbackToOcr, isFalse);
  });

  test('401 -> ProductLookupError (sign in)', () async {
    final r = await lookupProduct(_dioReturning(401, {'detail': 'nope'}), '123456789012');
    expect(r, isA<ProductLookupError>());
    expect((r as ProductLookupError).message.toLowerCase(), contains('sign in'));
  });

  test('422 -> ProductLookupError (invalid barcode)', () async {
    final r = await lookupProduct(_dioReturning(422, {'detail': 'bad'}), 'abc');
    expect((r as ProductLookupError).message.toLowerCase(), contains('barcode'));
  });

  test('5xx -> ProductLookupError, does not throw', () async {
    final r = await lookupProduct(_dioReturning(503, {'detail': 'down'}), '123456789012');
    expect(r, isA<ProductLookupError>());
  });

  test('connection failure -> friendly offline message', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = _FakeAdapter((o) {
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    });
    final r = await lookupProduct(dio, '123456789012');
    expect((r as ProductLookupError).message.toLowerCase(), contains('connection'));
  });

  test('productLookupProvider attaches the auth token as a Bearer header', () async {
    final adapter = _FakeAdapter((_) => ResponseBody.fromString(
          jsonEncode(_productJson),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          },
        ));

    final container = ProviderContainer(overrides: [
      dioProvider.overrideWith((ref) {
        final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
        dio.httpClientAdapter = adapter;
        dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          final t = ref.read(authTokenProvider);
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          handler.next(options);
        }));
        return dio;
      }),
    ]);
    addTearDown(container.dispose);

    container.read(authTokenProvider.notifier).set('jwt-123');
    await container.read(productLookupProvider)('3017620422003');

    expect(adapter.lastRequest?.headers['Authorization'], 'Bearer jwt-123');
    expect(adapter.lastRequest?.path, '/products/3017620422003');
  });
}
