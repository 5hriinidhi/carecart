import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'product_api.dart' show networkErrorMessage;

/// The lifestyle inputs to the CareCart Fit score: sleep, exercise, smoking,
/// alcohol, stress. Every field is optional.
class LifestyleProfile {
  const LifestyleProfile({
    this.sleepHours,
    this.exerciseDays,
    this.smoking,
    this.alcohol,
    this.stress,
  });

  final double? sleepHours;
  final int? exerciseDays; // 0..7
  final String? smoking; // none | occasional | daily
  final String? alcohol; // none | occasional | weekly | daily
  final int? stress; // 1..5

  bool get isEmpty =>
      sleepHours == null &&
      exerciseDays == null &&
      smoking == null &&
      alcohol == null &&
      stress == null;

  Map<String, dynamic> toJson() => {
        if (sleepHours != null) 'sleep_hours': sleepHours,
        if (exerciseDays != null) 'exercise_days': exerciseDays,
        if (smoking != null) 'smoking': smoking,
        if (alcohol != null) 'alcohol': alcohol,
        if (stress != null) 'stress': stress,
      };

  factory LifestyleProfile.fromJson(Map<String, dynamic> j) => LifestyleProfile(
        sleepHours: (j['sleep_hours'] as num?)?.toDouble(),
        exerciseDays: (j['exercise_days'] as num?)?.toInt(),
        smoking: j['smoking'] as String?,
        alcohol: j['alcohol'] as String?,
        stress: (j['stress'] as num?)?.toInt(),
      );

  LifestyleProfile copyWith({
    double? sleepHours,
    int? exerciseDays,
    String? smoking,
    String? alcohol,
    int? stress,
  }) =>
      LifestyleProfile(
        sleepHours: sleepHours ?? this.sleepHours,
        exerciseDays: exerciseDays ?? this.exerciseDays,
        smoking: smoking ?? this.smoking,
        alcohol: alcohol ?? this.alcohol,
        stress: stress ?? this.stress,
      );
}

abstract class LifestyleApi {
  /// null when the user has no lifestyle profile yet (404).
  Future<LifestyleProfile?> fetch();

  /// PUT — replace the whole profile. Returns null on success, a message on
  /// failure.
  Future<String?> put(LifestyleProfile profile);
}

class HttpLifestyleApi implements LifestyleApi {
  HttpLifestyleApi(this._dio);
  final Dio _dio;
  static final _opts = Options(validateStatus: (s) => s != null);

  @override
  Future<LifestyleProfile?> fetch() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
          '/me/lifestyle-profile', options: _opts);
      if (res.statusCode == 200) {
        return LifestyleProfile.fromJson(res.data ?? const {});
      }
      return null; // 404 or anything else -> "not set"
    } on DioException {
      return null;
    }
  }

  @override
  Future<String?> put(LifestyleProfile profile) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/me/lifestyle-profile',
        data: profile.toJson(),
        options: _opts,
      );
      if (res.statusCode == 200) return null;
      return "Couldn't save your lifestyle answers (${res.statusCode}).";
    } on DioException catch (e) {
      return networkErrorMessage(e,
          fallback: "Couldn't save your lifestyle answers.");
    }
  }
}

final lifestyleApiProvider =
    Provider<LifestyleApi>((ref) => HttpLifestyleApi(ref.read(dioProvider)));

final lifestyleProfileProvider =
    FutureProvider.autoDispose<LifestyleProfile?>(
        (ref) => ref.read(lifestyleApiProvider).fetch());
