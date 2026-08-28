// POST /products/resolve-risks client (Phase 4.3) — offline ingredient -> risk
// resolution. The "unverified" caution must survive parsing intact.

import 'dart:convert';
import 'dart:typed_data';

import 'package:carecart/src/core/product_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);
  final ResponseBody Function(RequestOptions options) responder;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
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

const _ok = {
  'ingredients': [
    {
      'input_text': 'Iodised salt',
      'clean_text': 'iodised salt',
      'risk_compounds': ['sodium'],
      'method': 'keyword',
      'confidence': 0.9,
    },
    {
      'input_text': 'mystery bark powder',
      'clean_text': 'mystery bark powder',
      'risk_compounds': <String>[],
      'method': 'unverified',
      'confidence': null,
    },
  ],
  'product_tags': [
    {
      'risk_compound': 'added_sugar',
      'nutrient_key': 'sugars_g_100g',
      'value': 30.0,
      'threshold': 22.5,
      'confidence': 0.7,
      'method': 'threshold',
      'rationale': 'FSA high',
    },
  ],
  'risk_compounds': {'sodium': 0.9, 'added_sugar': 0.7},
  'unverified': ['mystery bark powder'],
  'unverified_count': 1,
  'caution_factors': ["We couldn't confirm 1 ingredient in this product."],
  'resolved_count': 1,
  'benign_count': 0,
};

void main() {
  test('200 -> RiskResolutionReady with compounds, tags and the unverified caution', () async {
    final r = await resolveRisks(_dio(200, _ok), ingredients: ['Iodised salt', 'mystery bark powder']);

    expect(r, isA<RiskResolutionReady>());
    final res = (r as RiskResolutionReady).resolution;
    expect(res.riskCompounds['sodium'], 0.9);
    expect(res.riskCompounds['added_sugar'], 0.7);
    expect(res.productTags.single.riskCompound, 'added_sugar');
    expect(res.unverified, ['mystery bark powder']);
    expect(res.unverifiedCount, 1);
    expect(res.cautionFactors, ["We couldn't confirm 1 ingredient in this product."]);
    expect(res.ingredients.firstWhere((i) => i.isUnverified).cleanText, 'mystery bark powder');
    expect(res.resolvedCount, 1);
  });

  test('request carries ingredients + nutriments + barcode', () async {
    final adapter = _FakeAdapter((_) => ResponseBody.fromString(
          jsonEncode(_ok),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          },
        ));
    await resolveRisks(
      _dio(200, _ok, adapter: adapter),
      ingredients: ['salt'],
      nutriments: {'sodium_mg_100g': 800},
      barcode: '8901234567890',
    );
    final raw = adapter.lastRequest!.data;
    final body = (raw is String ? jsonDecode(raw) : raw) as Map;
    expect(body['ingredients'], ['salt']);
    expect(body['nutriments'], {'sodium_mg_100g': 800});
    expect(body['barcode'], '8901234567890');
  });

  test('unverified list defaults to empty, never null', () {
    final res = RiskResolution.fromJson({'risk_compounds': <String, dynamic>{}});
    expect(res.unverified, isEmpty);
    expect(res.cautionFactors, isEmpty);
    expect(res.ingredients, isEmpty);
  });

  test('401 -> RiskResolutionFailed(sign in)', () async {
    final r = await resolveRisks(_dio(401, {'detail': 'x'}), ingredients: ['salt']);
    expect(r, isA<RiskResolutionFailed>());
    expect((r as RiskResolutionFailed).message, 'Please sign in again.');
  });

  test('connection error -> offline message, never throws', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = _FakeAdapter((options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ));
    final r = await resolveRisks(dio, ingredients: ['salt']);
    expect((r as RiskResolutionFailed).message, 'No connection to the server.');
  });
}
