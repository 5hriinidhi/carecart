import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// A product returned by `GET /products/{barcode}` (Open Food Facts, normalised
/// + cached by the backend). Phase 4.2 turns this into a personalised verdict.
class ScannedProduct {
  const ScannedProduct({
    required this.barcode,
    this.name,
    this.brand,
    this.ingredients = const [],
    this.ingredientsText,
    this.nutriments = const {},
    this.servingSize,
    this.imageUrl,
    this.cached = false,
    this.stale = false,
  });

  final String barcode;
  final String? name;
  final String? brand;
  final List<String> ingredients;
  final String? ingredientsText;

  /// Normalised nutrition per 100 g (keys like `sugars_g_100g`, `sodium_mg_100g`).
  final Map<String, dynamic> nutriments;
  final String? servingSize;
  final String? imageUrl;

  /// Served from the backend cache without a fresh Open Food Facts call.
  final bool cached;

  /// The source was unreachable and an expired cache entry was served.
  final bool stale;

  String get displayName => (name != null && name!.trim().isNotEmpty)
      ? name!.trim()
      : 'Unnamed product';

  factory ScannedProduct.fromJson(Map<String, dynamic> j) => ScannedProduct(
        barcode: j['barcode'] as String? ?? '',
        name: j['name'] as String?,
        brand: j['brand'] as String?,
        ingredients:
            (j['ingredients'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        ingredientsText: j['ingredients_text'] as String?,
        nutriments: (j['nutriments'] as Map?)?.cast<String, dynamic>() ??
            const {},
        servingSize: j['serving_size'] as String?,
        imageUrl: j['image_url'] as String?,
        cached: j['cached'] as bool? ?? false,
        stale: j['stale'] as bool? ?? false,
      );
}

/// Outcome of a barcode lookup.
sealed class ProductLookup {
  const ProductLookup();
}

class ProductFound extends ProductLookup {
  const ProductFound(this.product);
  final ScannedProduct product;
}

/// The backend has no such barcode. [fallbackToOcr] mirrors the response's
/// `fallback: "ocr"` flag — the client should offer ingredient-list scanning.
class ProductNotFound extends ProductLookup {
  const ProductNotFound(this.barcode, {this.fallbackToOcr = true});
  final String barcode;
  final bool fallbackToOcr;
}

class ProductLookupError extends ProductLookup {
  const ProductLookupError(this.message);
  final String message;
}

/// One `GET /api/v1/products/{barcode}`. Never throws — every outcome is a
/// [ProductLookup] value the UI can render.
Future<ProductLookup> lookupProduct(Dio dio, String barcode) async {
  final code = barcode.trim();
  try {
    final res = await dio.get<Map<String, dynamic>>(
      '/products/$code',
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    final status = res.statusCode ?? 0;
    final data = res.data ?? const <String, dynamic>{};

    return switch (status) {
      200 => ProductFound(ScannedProduct.fromJson(data)),
      404 => ProductNotFound(code, fallbackToOcr: data['fallback'] == 'ocr'),
      401 => const ProductLookupError('Please sign in again.'),
      422 => const ProductLookupError("That barcode doesn't look valid."),
      _ => ProductLookupError('Product lookup failed ($status).'),
    };
  } on DioException catch (e) {
    final offline = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout;
    return ProductLookupError(
        offline ? 'No connection to the server.' : 'Product lookup failed.');
  }
}

/// Injectable lookup function — override in tests, or point at a fake backend.
final productLookupProvider = Provider<Future<ProductLookup> Function(String)>(
  (ref) => (barcode) => lookupProduct(ref.read(dioProvider), barcode),
);
