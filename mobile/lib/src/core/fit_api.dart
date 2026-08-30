import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// One lifestyle dimension's contribution to the Fit score.
class FitDim {
  const FitDim(
      {required this.key,
      required this.label,
      required this.score,
      required this.weight,
      required this.detail});
  final String key;
  final String label;
  final int score;
  final double weight;
  final String detail;

  factory FitDim.fromJson(Map<String, dynamic> j) => FitDim(
        key: j['key'] as String? ?? '',
        label: j['label'] as String? ?? '',
        score: (j['score'] as num?)?.toInt() ?? 0,
        weight: (j['weight'] as num?)?.toDouble() ?? 0,
        detail: j['detail'] as String? ?? '',
      );
}

class FitLifestyle {
  const FitLifestyle(
      {this.overall, this.answered = 0, this.total = 5, this.dims = const []});
  final int? overall;
  final int answered;
  final int total;
  final List<FitDim> dims;

  factory FitLifestyle.fromJson(Map<String, dynamic> j) => FitLifestyle(
        overall: (j['overall'] as num?)?.toInt(),
        answered: (j['answered'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 5,
        dims: ((j['dims'] as List?) ?? const [])
            .map((e) => FitDim.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One medication's standing against the user's recent scans.
class FitMed {
  const FitMed(
      {required this.name,
      required this.identified,
      this.score,
      required this.note,
      this.interactions = const []});
  final String name;
  final bool identified;
  final int? score; // null = not enough recent scans to assess
  final String note;
  final List<String> interactions;

  factory FitMed.fromJson(Map<String, dynamic> j) => FitMed(
        name: j['name'] as String? ?? '',
        identified: j['identified'] as bool? ?? false,
        score: (j['score'] as num?)?.toInt(),
        note: j['note'] as String? ?? '',
        interactions: ((j['interactions'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class FitMedicines {
  const FitMedicines(
      {this.overall, this.scansInWindow = 0, this.meds = const []});
  final int? overall;
  final int scansInWindow;
  final List<FitMed> meds;

  factory FitMedicines.fromJson(Map<String, dynamic> j) => FitMedicines(
        overall: (j['overall'] as num?)?.toInt(),
        scansInWindow: (j['scans_in_window'] as num?)?.toInt() ?? 0,
        meds: ((j['meds'] as List?) ?? const [])
            .map((e) => FitMed.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class FitFocus {
  const FitFocus(
      {required this.area,
      required this.label,
      required this.score,
      required this.message});
  final String area; // lifestyle | medicines
  final String label;
  final int score;
  final String message;

  factory FitFocus.fromJson(Map<String, dynamic> j) => FitFocus(
        area: j['area'] as String? ?? '',
        label: j['label'] as String? ?? '',
        score: (j['score'] as num?)?.toInt() ?? 0,
        message: j['message'] as String? ?? '',
      );
}

class Fit {
  const Fit({
    this.score,
    this.tier,
    this.delta = 0,
    required this.lifestyle,
    required this.medicines,
    this.focus,
  });

  final int? score;
  final String? tier;
  final int delta;
  final FitLifestyle lifestyle;
  final FitMedicines medicines;
  final FitFocus? focus;

  bool get hasAnything => score != null;

  factory Fit.fromJson(Map<String, dynamic> j) => Fit(
        score: (j['score'] as num?)?.toInt(),
        tier: j['tier'] as String?,
        delta: (j['delta'] as num?)?.toInt() ?? 0,
        lifestyle: FitLifestyle.fromJson(
            (j['lifestyle'] as Map?)?.cast<String, dynamic>() ?? const {}),
        medicines: FitMedicines.fromJson(
            (j['medicines'] as Map?)?.cast<String, dynamic>() ?? const {}),
        focus: j['focus'] == null
            ? null
            : FitFocus.fromJson((j['focus'] as Map).cast<String, dynamic>()),
      );
}

sealed class FitResult {
  const FitResult();
}

class FitLoaded extends FitResult {
  const FitLoaded(this.fit);
  final Fit fit;
}

class FitFailed extends FitResult {
  const FitFailed(this.message);
  final String message;
}

abstract class FitApi {
  Future<FitResult> fetch();
}

class HttpFitApi implements FitApi {
  HttpFitApi(this._dio);
  final Dio _dio;

  @override
  Future<FitResult> fetch() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/me/fit',
        options: Options(validateStatus: (s) => s != null),
      );
      if (res.statusCode == 200) {
        return FitLoaded(Fit.fromJson(res.data ?? const {}));
      }
      if (res.statusCode == 401) {
        return const FitFailed('Please sign in again.');
      }
      return FitFailed("Couldn't load your Fit score (${res.statusCode}).");
    } on DioException {
      return const FitFailed("Couldn't reach the server for your Fit score.");
    }
  }
}

final fitApiProvider = Provider<FitApi>((ref) => HttpFitApi(ref.read(dioProvider)));

final fitProvider =
    FutureProvider.autoDispose<FitResult>((ref) => ref.read(fitApiProvider).fetch());
