import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'connectivity.dart';
import 'local_cache.dart';

/// Turn a Dio failure into a short, honest, user-facing line. A timeout (Open
/// Food Facts or the backend slow / rate-limited mid-scan) is called out
/// separately from a hard "no connection" so the UI never just says "offline"
/// when the phone actually has signal — and never spins forever (Dio's
/// connect/receive timeouts in [dioProvider] guarantee this catch is reached).
String networkErrorMessage(DioException e, {required String fallback}) {
  return switch (e.type) {
    DioExceptionType.connectionError => 'No connection to the server.',
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout =>
      'The server is taking too long to respond. Check your connection and try again.',
    _ => fallback,
  };
}

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
    this.fromLocalCache = false,
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

  /// Served from the on-device cache because the backend was unreachable
  /// (Phase 6.3). The screen shows an "offline — saved copy" state.
  final bool fromLocalCache;

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

  /// Round-trips through [ScannedProduct.fromJson] — used by the on-device cache.
  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        'name': name,
        'brand': brand,
        'ingredients': ingredients,
        'ingredients_text': ingredientsText,
        'nutriments': nutriments,
        'serving_size': servingSize,
        'image_url': imageUrl,
        'cached': cached,
        'stale': stale,
      };

  ScannedProduct copyWith({bool? cached, bool? stale, bool? fromLocalCache}) =>
      ScannedProduct(
        barcode: barcode,
        name: name,
        brand: brand,
        ingredients: ingredients,
        ingredientsText: ingredientsText,
        nutriments: nutriments,
        servingSize: servingSize,
        imageUrl: imageUrl,
        cached: cached ?? this.cached,
        stale: stale ?? this.stale,
        fromLocalCache: fromLocalCache ?? this.fromLocalCache,
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
    return ProductLookupError(
        networkErrorMessage(e, fallback: 'Product lookup failed.'));
  }
}

/// Injectable lookup function — override in tests, or point at a fake backend.
///
/// Phase 6.3: a successful lookup is cached on-device; if a later lookup for a
/// known barcode fails because the backend is unreachable, the saved copy is
/// returned with [ScannedProduct.fromLocalCache] set so the screen can say
/// "offline — showing saved details".
final productLookupProvider = Provider<Future<ProductLookup> Function(String)>(
  (ref) => (barcode) async {
    final code = barcode.trim();
    final cache = ref.read(localCacheProvider);
    final result = await lookupProduct(ref.read(dioProvider), code);
    switch (result) {
      case ProductFound(:final product):
        await cache.putProduct(product);
        return result;
      case ProductLookupError():
        if (ref.read(isOfflineProvider)) {
          final hit = await cache.getProduct(code);
          if (hit != null) {
            return ProductFound(
                hit.product.copyWith(fromLocalCache: true, stale: true));
          }
        }
        return result;
      case ProductNotFound():
        return result;
    }
  },
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
    return IngredientScanFailed(
        networkErrorMessage(e, fallback: "Couldn't read the label."));
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
    return RiskResolutionFailed(networkErrorMessage(e,
        fallback: "Couldn't check this product's ingredients."));
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

// ---------------------------------------------------------------------------
// Scan verdict (Phase 4.4). The backend scores the product's ingredients +
// nutriments against the signed-in user's stored conditions, allergies and
// active medications and returns a 0–100 [score] + [tier] (safe/caution/avoid,
// the exact Phase 2.1 thresholds). An allergen match forces [hardStop] and
// tier "avoid" regardless of score.
// ---------------------------------------------------------------------------

class VerdictReason {
  const VerdictReason({
    required this.kind,
    required this.severity,
    required this.points,
    required this.title,
    this.detail,
  });

  /// allergen | drug_interaction | condition_ceiling | condition_compound |
  /// poor_fit | unverified | clear
  final String kind;

  /// high | moderate | low | info
  final String severity;

  /// Score deducted for this factor (0 for a hard stop / info line).
  final int points;
  final String title;
  final String? detail;

  bool get isAllergen => kind == 'allergen';

  factory VerdictReason.fromJson(Map<String, dynamic> j) => VerdictReason(
        kind: j['kind'] as String? ?? '',
        severity: j['severity'] as String? ?? 'info',
        points: (j['points'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        detail: j['detail'] as String?,
      );
}

class MedMatch {
  const MedMatch({
    required this.name,
    this.drugClasses = const [],
    this.identified = false,
  });

  final String name;
  final List<String> drugClasses;
  final bool identified;

  factory MedMatch.fromJson(Map<String, dynamic> j) => MedMatch(
        name: j['name'] as String? ?? '',
        drugClasses:
            (j['drug_classes'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        identified: j['identified'] as bool? ?? false,
      );
}

/// A nudge freshly generated by this scan (Phase 5.3). Minimal — the nudge
/// screen fetches the full list from GET /nudges.
class ScanNudge {
  const ScanNudge({required this.id, required this.factor, required this.message});
  final String id;
  final String factor;
  final String message;

  factory ScanNudge.fromJson(Map<String, dynamic> j) => ScanNudge(
        id: j['id']?.toString() ?? '',
        factor: j['factor'] as String? ?? '',
        message: j['message'] as String? ?? '',
      );
}

class ScanVerdict {
  const ScanVerdict({
    required this.score,
    required this.tier,
    required this.hardStop,
    this.reasons = const [],
    this.medications = const [],
    this.riskCompounds = const {},
    this.unverified = const [],
    this.unverifiedCount = 0,
    this.nudge,
  });

  final int score;

  /// safe | caution | avoid
  final String tier;

  /// True when an allergen match forced "avoid" regardless of the number.
  final bool hardStop;
  final List<VerdictReason> reasons;
  final List<MedMatch> medications;
  final Map<String, double> riskCompounds;
  final List<String> unverified;
  final int unverifiedCount;

  /// Set only when THIS scan crossed a 14-day pattern threshold.
  final ScanNudge? nudge;

  factory ScanVerdict.fromJson(Map<String, dynamic> j) => ScanVerdict(
        score: (j['score'] as num?)?.toInt() ?? 0,
        tier: j['tier'] as String? ?? 'avoid',
        hardStop: j['hard_stop'] as bool? ?? false,
        reasons: (j['reasons'] as List?)
                ?.map((e) => VerdictReason.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        medications: (j['medications'] as List?)
                ?.map((e) => MedMatch.fromJson(e as Map<String, dynamic>))
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
        nudge: j['nudge'] is Map<String, dynamic>
            ? ScanNudge.fromJson(j['nudge'] as Map<String, dynamic>)
            : null,
      );
}

sealed class ScanVerdictOutcome {
  const ScanVerdictOutcome();
}

class ScanVerdictReady extends ScanVerdictOutcome {
  const ScanVerdictReady(this.verdict);
  final ScanVerdict verdict;
}

class ScanVerdictFailed extends ScanVerdictOutcome {
  const ScanVerdictFailed(this.message);
  final String message;
}

/// One `POST /api/v1/scan/verdict`. Never throws.
Future<ScanVerdictOutcome> scanVerdict(
  Dio dio, {
  required List<String> ingredients,
  Map<String, num> nutriments = const {},
  String? barcode,
  String? productName,
}) async {
  try {
    final res = await dio.post<Map<String, dynamic>>(
      '/scan/verdict',
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
      return ScanVerdictReady(ScanVerdict.fromJson(res.data ?? const {}));
    }
    return ScanVerdictFailed(switch (status) {
      401 => 'Please sign in again.',
      422 => "That scan didn't look valid.",
      _ => "Couldn't score this product ($status).",
    });
  } on DioException catch (e) {
    return ScanVerdictFailed(
        networkErrorMessage(e, fallback: "Couldn't score this product."));
  }
}

/// Injectable — override in tests.
final scanVerdictProvider = Provider<
    Future<ScanVerdictOutcome> Function({
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
      scanVerdict(
        ref.read(dioProvider),
        ingredients: ingredients,
        nutriments: nutriments,
        barcode: barcode,
        productName: productName,
      ),
);
