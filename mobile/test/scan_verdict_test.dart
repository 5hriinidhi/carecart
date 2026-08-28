// POST /scan/verdict client (Phase 4.4) — food-drug interaction & severity
// scoring. The allergen hard-stop and the reason list must survive parsing.

import 'dart:convert';
import 'dart:typed_data';

import 'package:carecart/src/core/product_api.dart';
import 'package:carecart/src/core/severity.dart';
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

const _caution = {
  'score': 65,
  'tier': 'caution',
  'hard_stop': false,
  'reasons': [
    {
      'kind': 'drug_interaction',
      'severity': 'high',
      'points': 35,
      'title': 'Warfarin (Anticoagulant (vitamin K antagonist)) interacts with Vitamin K',
      'detail': 'Keep leafy-green intake consistent day to day.',
    },
  ],
  'medications': [
    {
      'name': 'Warfarin 5mg',
      'drug_classes': ['Anticoagulant (vitamin K antagonist)'],
      'identified': true,
    },
  ],
  'risk_compounds': {'vitamin_k': 0.9},
  'unverified': <String>[],
  'unverified_count': 0,
};

const _hardStop = {
  'score': 0,
  'tier': 'avoid',
  'hard_stop': true,
  'reasons': [
    {
      'kind': 'allergen',
      'severity': 'high',
      'points': 0,
      'title': "Contains Tree nuts & peanut (allergen) — you told us you're allergic to Peanuts",
      'detail': 'Ingredient flagged: "Groundnut".',
    },
  ],
  'medications': <Map<String, dynamic>>[],
  'risk_compounds': {'nut_allergen': 0.9},
  'unverified': <String>[],
  'unverified_count': 0,
};

void main() {
  test('200 -> ScanVerdictReady, tier + reasons + med match parsed', () async {
    final r = await scanVerdict(_dio(200, _caution),
        ingredients: ['Broccoli', 'Water'], nutriments: {'sodium_mg_100g': 20});

    expect(r, isA<ScanVerdictReady>());
    final v = (r as ScanVerdictReady).verdict;
    expect(v.score, 65);
    expect(v.tier, 'caution');
    expect(v.hardStop, isFalse);
    expect(v.reasons.single.kind, 'drug_interaction');
    expect(v.reasons.single.points, 35);
    expect(v.medications.single.identified, isTrue);
    expect(v.medications.single.drugClasses, ['Anticoagulant (vitamin K antagonist)']);
    // the 0–100 score still maps through the Phase 2.1 chip helper
    expect(chipFor(v.score).tone, Severity.caution);
  });

  test('allergen hard-stop: score 0, tier avoid, allergen reason first', () async {
    final r = await scanVerdict(_dio(200, _hardStop), ingredients: ['Groundnut']);
    final v = (r as ScanVerdictReady).verdict;
    expect(v.hardStop, isTrue);
    expect(v.tier, 'avoid');
    expect(v.score, 0);
    expect(v.reasons.first.isAllergen, isTrue);
    expect(v.reasons.first.points, 0);
    expect(chipFor(v.score).tone, Severity.avoid);
  });

  test('request carries ingredients + nutriments + barcode', () async {
    final adapter = _FakeAdapter((_) => ResponseBody.fromString(
          jsonEncode(_caution),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          },
        ));
    await scanVerdict(_dio(200, _caution, adapter: adapter),
        ingredients: ['Broccoli'],
        nutriments: {'sodium_mg_100g': 800},
        barcode: '8901234567890');
    final raw = adapter.lastRequest!.data;
    final body = (raw is String ? jsonDecode(raw) : raw) as Map;
    expect(body['ingredients'], ['Broccoli']);
    expect(body['nutriments'], {'sodium_mg_100g': 800});
    expect(body['barcode'], '8901234567890');
    expect(body.containsKey('product_name'), isFalse); // null omitted
  });

  test('missing fields default safely', () {
    final v = ScanVerdict.fromJson({'score': 100, 'tier': 'safe', 'hard_stop': false});
    expect(v.reasons, isEmpty);
    expect(v.medications, isEmpty);
    expect(v.unverified, isEmpty);
  });

  test('401 -> ScanVerdictFailed(sign in)', () async {
    final r = await scanVerdict(_dio(401, {'detail': 'x'}), ingredients: ['salt']);
    expect((r as ScanVerdictFailed).message, 'Please sign in again.');
  });

  test('connection error -> offline message, never throws', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = _FakeAdapter((options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ));
    final r = await scanVerdict(dio, ingredients: ['salt']);
    expect((r as ScanVerdictFailed).message, 'No connection to the server.');
  });
}
