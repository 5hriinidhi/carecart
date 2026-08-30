import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'product_api.dart' show networkErrorMessage;

/// One hit from `GET /api/v1/foods/search` — a home dish or a packaged product
/// from the everyday-food dataset. A search-only alternative to a barcode scan.
class FoodHit {
  const FoodHit({
    required this.name,
    required this.kind, // 'dish' | 'packaged'
    this.brand,
    this.category,
    this.ingredientsText,
    this.diet,
    this.course,
    this.region,
    this.servingSize,
    this.nutriments = const {},
  });

  final String name;
  final String kind;
  final String? brand;
  final String? category;
  final String? ingredientsText;
  final String? diet;
  final String? course;
  final String? region;
  final String? servingSize;
  final Map<String, dynamic> nutriments;

  bool get isPackaged => kind == 'packaged';

  /// One-line context for a results row.
  String get subtitle {
    final bits = <String>[
      if ((brand ?? '').trim().isNotEmpty) brand!.trim(),
      if ((category ?? '').trim().isNotEmpty) category!.trim(),
      if (!isPackaged && (course ?? '').trim().isNotEmpty) course!.trim(),
      if (!isPackaged && (region ?? '').trim().isNotEmpty) region!.trim(),
    ];
    return bits.join(' · ');
  }

  factory FoodHit.fromJson(Map<String, dynamic> j) => FoodHit(
        name: (j['name'] as String? ?? '').trim(),
        kind: (j['kind'] as String? ?? 'dish').trim(),
        brand: j['brand'] as String?,
        category: j['category'] as String?,
        ingredientsText: j['ingredients_text'] as String?,
        diet: j['diet'] as String?,
        course: j['course'] as String?,
        region: j['region'] as String?,
        servingSize: j['serving_size'] as String?,
        nutriments: (j['nutriments'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );
}

sealed class FoodSearchResult {
  const FoodSearchResult();
}

class FoodSearchHits extends FoodSearchResult {
  const FoodSearchHits(this.hits);
  final List<FoodHit> hits;
}

class FoodSearchError extends FoodSearchResult {
  const FoodSearchError(this.message);
  final String message;
}

abstract class FoodsApi {
  Future<FoodSearchResult> search(String query, {int limit});
}

class HttpFoodsApi implements FoodsApi {
  HttpFoodsApi(this._dio);
  final Dio _dio;

  @override
  Future<FoodSearchResult> search(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.replaceAll(RegExp(r'\s'), '').length < 2) {
      return const FoodSearchHits([]);
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/foods/search',
        queryParameters: {'q': q, 'limit': limit},
        options: Options(validateStatus: (s) => s != null),
      );
      if (res.statusCode == 200) {
        final list = (res.data?['results'] as List?) ?? const [];
        return FoodSearchHits(
          list
              .map((e) => FoodHit.fromJson(e as Map<String, dynamic>))
              .where((f) => f.name.isNotEmpty)
              .toList(),
        );
      }
      if (res.statusCode == 401) {
        return const FoodSearchError('Please sign in again.');
      }
      return FoodSearchError('Search failed (${res.statusCode}).');
    } on DioException catch (e) {
      return FoodSearchError(
          networkErrorMessage(e, fallback: "Couldn't reach the food list."));
    }
  }
}

final foodsApiProvider =
    Provider<FoodsApi>((ref) => HttpFoodsApi(ref.read(dioProvider)));
