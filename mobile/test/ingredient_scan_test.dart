// POST /products/scan-label client (Phase 4.2) — OCR ingredient-list fallback.

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

Dio _dio(int status, Object body, {_FakeAdapter? adapter}) {
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

final _bytes = Uint8List.fromList(List<int>.filled(64, 1));

void main() {
  test('200 -> IngredientScanReady with parsed list + raw text + editable flag', () async {
    final r = await scanIngredientLabel(
      _dio(200, {
        'ingredients': ['water', 'sugar', 'iodised salt'],
        'raw_text': 'INGREDIENTS: water, sugar, iodised salt',
        'raw_text_truncated': false,
        'editable': true,
        'source': 'ocr',
      }),
      _bytes,
    );
    expect(r, isA<IngredientScanReady>());
    final res = (r as IngredientScanReady).result;
    expect(res.ingredients, ['water', 'sugar', 'iodised salt']);
    expect(res.rawText, 'INGREDIENTS: water, sugar, iodised salt');
    expect(res.editable, isTrue);
    expect(res.rawTextTruncated, isFalse);
  });

  test('editable defaults to true even if the field is missing', () {
    final res = IngredientScanResult.fromJson({'raw_text': 'x'});
    expect(res.editable, isTrue);
    expect(res.ingredients, isEmpty);
  });

  test('415/422 -> "not a photo of a label"', () async {
    final r = await scanIngredientLabel(_dio(422, {'detail': 'bad'}), _bytes);
    expect((r as IngredientScanFailed).message.toLowerCase(), contains('label'));
  });

  test('413 -> too large', () async {
    final r = await scanIngredientLabel(_dio(413, {'detail': 'big'}), _bytes);
    expect((r as IngredientScanFailed).message.toLowerCase(), contains('large'));
  });

  test('503 -> unavailable', () async {
    final r = await scanIngredientLabel(_dio(503, {'detail': 'down'}), _bytes);
    expect((r as IngredientScanFailed).message.toLowerCase(), contains('unavailable'));
  });

  test('5xx -> failure, never throws', () async {
    final r = await scanIngredientLabel(_dio(500, {'detail': 'boom'}), _bytes);
    expect(r, isA<IngredientScanFailed>());
  });

  test('connection failure -> offline message', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = _FakeAdapter((o) {
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    });
    final r = await scanIngredientLabel(dio, _bytes);
    expect((r as IngredientScanFailed).message.toLowerCase(), contains('connection'));
  });

  test('sends a multipart POST to /products/scan-label with the auth token', () async {
    final adapter = _FakeAdapter((_) => ResponseBody.fromString(
          jsonEncode({'ingredients': ['a'], 'raw_text': 'a'}),
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
    container.read(authTokenProvider.notifier).set('jwt-xyz');

    await container.read(ingredientLabelScanProvider)(_bytes);

    expect(adapter.lastRequest?.method, 'POST');
    expect(adapter.lastRequest?.path, '/products/scan-label');
    expect(adapter.lastRequest?.headers['Authorization'], 'Bearer jwt-xyz');
    expect(adapter.lastRequest?.data, isA<FormData>());
    expect((adapter.lastRequest?.data as FormData).files.first.key, 'file');
  });
}
