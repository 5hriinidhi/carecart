import 'dart:typed_data';

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

// ---------------------------------------------------------------------------
// Ingredient-label OCR fallback (Phase 4.2) — for products not in Open Food
// Facts. The parsed list is a DRAFT the user must be able to correct before
// it's used; the raw OCR text is returned so they can.
// ---------------------------------------------------------------------------

class IngredientScanResult {
  const IngredientScanResult({
    required this.ingredients,
    required this.rawText,
    this.rawTextTruncated = false,
    this.ocrConfidence = 0.0,
    this.lowConfidence = false,
    this.note,
    this.editable = true,
  });

  final List<String> ingredients;
  final String rawText;
  final bool rawTextTruncated;

  /// Mean OCR word confidence, 0–1.
  final double ocrConfidence;

  /// Blurry / rotated / dim, or nothing parseable — warn the user, don't proceed.
  final bool lowConfidence;

  /// Plain-language advice to show when [lowConfidence] is true.
  final String? note;

  /// Always true — the client must show an editable step, never auto-proceed.
  final bool editable;

  factory IngredientScanResult.fromJson(Map<String, dynamic> j) => IngredientScanResult(
        ingredients: (j['ingredients'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        rawText: j['raw_text'] as String? ?? '',
        rawTextTruncated: j['raw_text_truncated'] as bool? ?? false,
        ocrConfidence: (j['ocr_confidence'] as num?)?.toDouble() ?? 0.0,
        lowConfidence: j['low_confidence'] as bool? ?? false,
        note: j['note'] as String?,
        editable: j['editable'] as bool? ?? true,
      );
}

sealed class IngredientScan {
  const IngredientScan();
}

class IngredientScanReady extends IngredientScan {
  const IngredientScanReady(this.result);
  final IngredientScanResult result;
}

class IngredientScanFailed extends IngredientScan {
  const IngredientScanFailed(this.message);
  final String message;
}

/// One `POST /api/v1/products/scan-label` (multipart image). Never throws.
Future<IngredientScan> scanIngredientLabel(
  Dio dio,
  Uint8List imageBytes, {
  String filename = 'label.jpg',
  String contentType = 'image/jpeg',
}) async {
  try {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        imageBytes,
        filename: filename,
        contentType: DioMediaType.parse(contentType),
      ),
    });
    final res = await dio.post<Map<String, dynamic>>(
      '/products/scan-label',
      data: form,
      options: Options(validateStatus: (s) => s != null), // handle every status here
    );
    final status = res.statusCode ?? 0;
    if (status == 200) {
      return IngredientScanReady(IngredientScanResult.fromJson(res.data ?? const {}));
    }
    return IngredientScanFailed(switch (status) {
      401 => 'Please sign in again.',
      413 => 'That photo is too large.',
      415 || 422 => "That doesn't look like a photo of a label.",
      503 => 'Label scanning is unavailable right now.',
      _ => "Couldn't read the label ($status).",
    });
  } on DioException catch (e) {
    final offline = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout;
    return IngredientScanFailed(
        offline ? 'No connection to the server.' : "Couldn't read the label.");
  }
}

/// Injectable — override in tests.
final ingredientLabelScanProvider =
    Provider<Future<IngredientScan> Function(Uint8List)>(
  (ref) => (bytes) => scanIngredientLabel(ref.read(dioProvider), bytes),
);

// ---------------------------------------------------------------------------
// Ingredient -> risk_compound resolution (Phase 4.3). The backend resolves the
// list entirely against pre-built static tables — no LLM, no network on its
// scan path. Ingredients it can't confirm come back method == "unverified" with
// a plain-language line in [cautionFactors]; Phase 4.4 scoring must surface
// that, never treat an unverified ingredient as safe.
// ---------------------------------------------------------------------------

class IngredientRisk {
  const IngredientRisk({
    required this.inputText,
    required this.cleanText,
    this.riskCompounds = const [],
    this.method = 'unverified',
    this.confidence,
  });

  final String inputText;
  final String cleanText;
  final List<String> riskCompounds;

  /// keyword | llm | benign | unverified
  final String method;
  final double? confidence;

  bool get isUnverified => method == 'unverified';

  factory IngredientRisk.fromJson(Map<String, dynamic> j) => IngredientRisk(
        inputText: j['input_text'] as String? ?? '',
        cleanText: j['clean_text'] as String? ?? '',
        riskCompounds:
            (j['risk_compounds'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        method: j['method'] as String? ?? 'unverified',
        confidence: (j['confidence'] as num?)?.toDouble(),
      );
}

class ProductRiskTag {
  const ProductRiskTag({
    required this.riskCompound,
    required this.nutrientKey,
    required this.value,
    required this.threshold,
    required this.confidence,
    this.method = 'threshold',
    this.rationale,
  });

  final String riskCompound;
  final String nutrientKey;
  final double value;
  final double threshold;
  final double confidence;
  final String method;
  final String? rationale;

  factory ProductRiskTag.fromJson(Map<String, dynamic> j) => ProductRiskTag(
        riskCompound: j['risk_compound'] as String? ?? '',
        nutrientKey: j['nutrient_key'] as String? ?? '',
        value: (j['value'] as num?)?.toDouble() ?? 0,
        threshold: (j['threshold'] as num?)?.toDouble() ?? 0,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        method: j['method'] as String? ?? 'threshold',
        rationale: j['rationale'] as String?,
      );
}

class RiskResolution {
  const RiskResolution({
    this.ingredients = const [],
    this.productTags = const [],
    this.riskCompounds = const {},
    this.unverified = const [],
    this.unverifiedCount = 0,
    this.cautionFactors = const [],
    this.resolvedCount = 0,
    this.benignCount = 0,
  });

  final List<IngredientRisk> ingredients;
  final List<ProductRiskTag> productTags;

  /// Union of every resolved compound -> its highest confidence. Phase 4.4
  /// severity scoring consumes this.
  final Map<String, double> riskCompounds;

  /// Cleaned ingredient texts the static tables could not confirm.
  final List<String> unverified;
  final int unverifiedCount;

  /// Human-readable cautions to show the user — includes the
  /// "couldn't confirm N ingredient(s)" line whenever [unverifiedCount] > 0.
  final List<String> cautionFactors;
  final int resolvedCount;
  final int benignCount;

  factory RiskResolution.fromJson(Map<String, dynamic> j) => RiskResolution(
        ingredients: (j['ingredients'] as List?)
                ?.map((e) => IngredientRisk.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        productTags: (j['product_tags'] as List?)
                ?.map((e) => ProductRiskTag.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        riskCompounds: (j['risk_compounds'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            ) ??
            const {},
        unverified:
            (j['unverified'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        unverifiedCount: (j['unverified_count'] as num?)?.toInt() ?? 0,
        cautionFactors:
            (j['caution_factors'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        resolvedCount: (j['resolved_count'] as num?)?.toInt() ?? 0,
        benignCount: (j['benign_count'] as num?)?.toInt() ?? 0,
      );
}

sealed class RiskResolutionOutcome {
  const RiskResolutionOutcome();
}

class RiskResolutionReady extends RiskResolutionOutcome {
  const RiskResolutionReady(this.resolution);
  final RiskResolution resolution;
}

class RiskResolutionFailed extends RiskResolutionOutcome {
  const RiskResolutionFailed(this.message);
  final String message;
}

/// One `POST /api/v1/products/resolve-risks`. Never throws.
Future<RiskResolutionOutcome> resolveRisks(
  Dio dio, {
  required List<String> ingredients,
  Map<String, num> nutriments = const {},
  String? barcode,
  String? productName,
}) async {
  try {
    final res = await dio.post<Map<String, dynamic>>(
      '/products/resolve-risks',
      data: {
        'ingredients': ingredients,
        'nutriments': nutriments,
        'barcode': ?barcode,
        'product_name': ?productName,
      },
      options: Options(validateStatus: (s) => s != null),
    );
    final status = res.statusCode ?? 0;
    if (status == 200) {
      return RiskResolutionReady(
          RiskResolution.fromJson(res.data ?? const {}));
    }
    return RiskResolutionFailed(switch (status) {
      401 => 'Please sign in again.',
      422 => "That ingredient list didn't look valid.",
      _ => "Couldn't check this product's ingredients ($status).",
    });
  } on DioException catch (e) {
    final offline = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout;
    return RiskResolutionFailed(offline
        ? 'No connection to the server.'
        : "Couldn't check this product's ingredients.");
  }
}

/// Injectable — override in tests.
final resolveRisksProvider = Provider<
    Future<RiskResolutionOutcome> Function({
      required List<String> ingredients,
      Map<String, num> nutriments,
      String? barcode,
      String? productName,
    })>(
  (ref) => ({
    required List<String> ingredients,
    Map<String, num> nutriments = const {},
    String? barcode,
    String? productName,
  }) =>
      resolveRisks(
        ref.read(dioProvider),
        ingredients: ingredients,
        nutriments: nutriments,
        barcode: barcode,
        productName: productName,
      ),
);
