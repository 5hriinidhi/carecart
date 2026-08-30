import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'product_api.dart' show networkErrorMessage;

/// One hit from `GET /api/v1/drugs/search` — a medicine brand the user can pick
/// when adding a medication, so they never have to type (or OCR) a raw name.
class DrugHit {
  const DrugHit({
    required this.name,
    this.saltComposition,
    this.activeIngredients,
    this.drugClasses,
  });

  final String name;
  final String? saltComposition;
  final String? activeIngredients;
  final String? drugClasses;

  /// A short second line for the picker row.
  String get subtitle {
    final s = (saltComposition ?? '').trim();
    if (s.isNotEmpty) return s;
    return (activeIngredients ?? '').trim();
  }

  factory DrugHit.fromJson(Map<String, dynamic> j) => DrugHit(
        name: (j['name'] as String? ?? '').trim(),
        saltComposition: j['salt_composition'] as String?,
        activeIngredients: j['active_ingredients'] as String?,
        drugClasses: j['drug_classes'] as String?,
      );
}

sealed class DrugSearchResult {
  const DrugSearchResult();
}

class DrugSearchHits extends DrugSearchResult {
  const DrugSearchHits(this.hits);
  final List<DrugHit> hits;
}

class DrugSearchError extends DrugSearchResult {
  const DrugSearchError(this.message);
  final String message;
}

/// The `/drugs/search` seam. A fake stands in for it in tests.
abstract class DrugsApi {
  /// Fewer than 2 non-space chars → an empty hit list, no request made.
  Future<DrugSearchResult> search(String query, {int limit});
}

class HttpDrugsApi implements DrugsApi {
  HttpDrugsApi(this._dio);
  final Dio _dio;

  @override
  Future<DrugSearchResult> search(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.replaceAll(RegExp(r'\s'), '').length < 2) {
      return const DrugSearchHits([]);
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/drugs/search',
        queryParameters: {'q': q, 'limit': limit},
        options: Options(validateStatus: (s) => s != null),
      );
      if (res.statusCode == 200) {
        final list = (res.data?['results'] as List?) ?? const [];
        return DrugSearchHits(
          list
              .map((e) => DrugHit.fromJson(e as Map<String, dynamic>))
              .where((d) => d.name.isNotEmpty)
              .toList(),
        );
      }
      if (res.statusCode == 401) {
        return const DrugSearchError('Please sign in again.');
      }
      return DrugSearchError('Search failed (${res.statusCode}).');
    } on DioException catch (e) {
      return DrugSearchError(
          networkErrorMessage(e, fallback: "Couldn't reach the medicine list."));
    }
  }
}

final drugsApiProvider =
    Provider<DrugsApi>((ref) => HttpDrugsApi(ref.read(dioProvider)));
