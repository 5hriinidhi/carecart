import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'product_api.dart' show networkErrorMessage;

/// Health-identity vault writes (Phase 3.2) + hard account deletion (Phase 3.4),
/// wired into the onboarding flow and the profile sheet.
///
/// Every call is authenticated by the Bearer token that [dioProvider] attaches;
/// they never throw — a failure comes back as [VaultError].

/// One saved medication row (`GET /api/v1/me/medications`).
class Medication {
  const Medication({
    required this.id,
    required this.name,
    this.dosage,
    this.activeFrom,
    this.activeTo,
  });

  final String id;
  final String name;
  final String? dosage;
  final DateTime? activeFrom;
  final DateTime? activeTo;

  factory Medication.fromJson(Map<String, dynamic> j) => Medication(
        id: j['id']?.toString() ?? '',
        name: j['name'] as String? ?? '',
        dosage: j['dosage'] as String?,
        activeFrom: DateTime.tryParse(j['active_from'] as String? ?? ''),
        activeTo: DateTime.tryParse(j['active_to'] as String? ?? ''),
      );
}

/// `GET /me/health-profile` payload — gender, activity, body metrics, diet.
class HealthProfileData {
  const HealthProfileData({
    this.gender,
    this.activityLevel,
    this.weight,
    this.height,
    this.weightUnit,
    this.heightUnit,
    this.diet = const [],
  });

  final String? gender;
  final String? activityLevel;
  final double? weight;
  final double? height;
  final String? weightUnit;
  final String? heightUnit;
  final List<String> diet;

  factory HealthProfileData.fromJson(Map<String, dynamic> j) {
    final bm = (j['body_metrics'] as Map?)?.cast<String, dynamic>() ?? const {};
    return HealthProfileData(
      gender: j['gender'] as String?,
      activityLevel: j['activity_level'] as String?,
      weight: (bm['weight'] as num?)?.toDouble(),
      height: (bm['height'] as num?)?.toDouble(),
      weightUnit: bm['weight_unit'] as String?,
      heightUnit: bm['height_unit'] as String?,
      diet: ((j['diet_type'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  HealthProfileData copyWith({
    String? gender,
    String? activityLevel,
    double? weight,
    double? height,
    String? weightUnit,
    String? heightUnit,
    List<String>? diet,
  }) =>
      HealthProfileData(
        gender: gender ?? this.gender,
        activityLevel: activityLevel ?? this.activityLevel,
        weight: weight ?? this.weight,
        height: height ?? this.height,
        weightUnit: weightUnit ?? this.weightUnit,
        heightUnit: heightUnit ?? this.heightUnit,
        diet: diet ?? this.diet,
      );
}

sealed class VaultWrite {
  const VaultWrite();
}

class VaultOk extends VaultWrite {
  const VaultOk();
}

class VaultError extends VaultWrite {
  const VaultError(this.message);
  final String message;
}

sealed class MedicationsResult {
  const MedicationsResult();
}

class MedicationsLoaded extends MedicationsResult {
  const MedicationsLoaded(this.items);
  final List<Medication> items;
}

class MedicationsFailed extends MedicationsResult {
  const MedicationsFailed(this.message);
  final String message;
}

class VaultApi {
  VaultApi(this._dio);
  final Dio _dio;

  static final _opts = Options(validateStatus: (s) => s != null);

  Future<VaultWrite> _send(
    String method,
    String path, {
    Object? body,
    Set<int> ok = const {200, 201, 204},
  }) async {
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: body,
        options: _opts.copyWith(method: method),
      );
      final status = res.statusCode ?? 0;
      if (ok.contains(status)) return const VaultOk();
      if (status == 401) return const VaultError('Please sign in again.');
      return VaultError("That didn't save ($status).");
    } on DioException catch (e) {
      return VaultError(networkErrorMessage(e, fallback: "That didn't save."));
    }
  }

  /// `GET /me/health-profile` — null when the user has none yet (404).
  Future<HealthProfileData?> fetchHealthProfile() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
          '/me/health-profile', options: _opts);
      if (res.statusCode == 200) {
        return HealthProfileData.fromJson(res.data ?? const {});
      }
      return null;
    } on DioException {
      return null;
    }
  }

  /// `PUT /me/health-profile` — onboarding steps 1–4 (gender, activity, body,
  /// diet). Upsert: safe to call again.
  Future<VaultWrite> putHealthProfile({
    String? gender,
    String? activityLevel,
    double? weight,
    double? height,
    String? weightUnit,
    String? heightUnit,
    List<String> diet = const [],
  }) =>
      _send('PUT', '/me/health-profile', body: {
        'gender': gender,
        'activity_level': activityLevel,
        'body_metrics': {
          'weight': weight,
          'height': height,
          'weight_unit': weightUnit,
          'height_unit': heightUnit,
        },
        'diet_type': diet,
      });

  /// `POST /me/allergies` — one per selected allergen (step 5).
  Future<VaultWrite> addAllergy(String name) =>
      _send('POST', '/me/allergies', body: {'allergen_name': name});

  /// `POST /me/conditions`.
  Future<VaultWrite> addCondition(String name) =>
      _send('POST', '/me/conditions', body: {'condition_name': name});

  /// `POST /me/medications` — one per entry the user confirmed (step 6).
  Future<VaultWrite> addMedication(String name,
          {String? dosage, DateTime? activeFrom}) =>
      _send('POST', '/me/medications', body: {
        'name': name,
        if (dosage != null && dosage.isNotEmpty) 'dosage': dosage,
        if (activeFrom != null)
          'active_from': activeFrom.toIso8601String().split('T').first,
      });

  /// `DELETE /me/medications/{id}` — remove one saved medication.
  Future<VaultWrite> deleteMedication(String id) =>
      _send('DELETE', '/me/medications/$id', ok: const {204});

  /// `GET /me/medications`.
  Future<MedicationsResult> fetchMedications() async {
    try {
      final res = await _dio.get<List<dynamic>>('/me/medications', options: _opts);
      final status = res.statusCode ?? 0;
      if (status == 200) {
        return MedicationsLoaded((res.data ?? const [])
            .map((e) => Medication.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return MedicationsFailed(status == 401
          ? 'Please sign in again.'
          : "Couldn't load your medications ($status).");
    } on DioException catch (e) {
      return MedicationsFailed(
          networkErrorMessage(e, fallback: "Couldn't load your medications."));
    }
  }

  /// `DELETE /me/account` — permanent, cascading hard delete.
  Future<VaultWrite> deleteAccount() =>
      _send('DELETE', '/me/account', ok: const {204});
}

final vaultApiProvider = Provider<VaultApi>((ref) => VaultApi(ref.read(dioProvider)));

/// Drives the meds screen. Auto-disposes so it refetches on reopen.
final medicationsProvider = FutureProvider.autoDispose<MedicationsResult>(
  (ref) => ref.read(vaultApiProvider).fetchMedications(),
);

/// Drives the profile page's health section.
final healthProfileProvider = FutureProvider.autoDispose<HealthProfileData?>(
  (ref) => ref.read(vaultApiProvider).fetchHealthProfile(),
);
