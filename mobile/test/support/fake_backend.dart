import 'package:carecart/src/core/analytics_api.dart';
import 'package:carecart/src/core/auth_api.dart';
import 'package:carecart/src/core/drugs_api.dart';
import 'package:carecart/src/core/fit_api.dart';
import 'package:carecart/src/core/foods_api.dart';
import 'package:carecart/src/core/history_api.dart';
import 'package:carecart/src/core/lifestyle_api.dart';
import 'package:carecart/src/core/me_api.dart';
import 'package:carecart/src/core/nudges_api.dart';
import 'package:carecart/src/core/vault_api.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// In-memory fakes for the backend seams the app now depends on, so widget /
/// state tests can drive the real onboarding + shell flow without a server.

class FakeAuthApi implements AuthApi {
  FakeAuthApi({
    this.devCode = '424242',
    this.isNewUser = true,
    this.requestFails,
    this.verifyFails,
  });

  /// null -> a dev backend that echoes this code; set to '' to simulate a
  /// production backend (no code echoed).
  String? devCode;
  bool isNewUser;
  String? requestFails; // non-null -> request-otp returns this error
  String? verifyFails; // non-null -> verify-otp returns this error

  final List<String> requestedPhones = [];
  final List<({String phone, String code})> verifiedWith = [];

  @override
  Future<RequestOtpResult> requestOtp(String phone) async {
    requestedPhones.add(phone);
    if (requestFails != null) return OtpRequestFailed(requestFails!);
    return OtpRequested(
        devCode: (devCode ?? '').isEmpty ? null : devCode, expiresIn: 300);
  }

  @override
  Future<VerifyOtpResult> verifyOtp(String phone, String code) async {
    verifiedWith.add((phone: phone, code: code));
    if (verifyFails != null) return OtpVerifyFailed(verifyFails!);
    return OtpVerified(AuthSession(
      accessToken: 'fake.access.$phone',
      refreshToken: 'fake.refresh.$phone',
      isNewUser: isNewUser,
    ));
  }
}

class FakeVaultApi implements VaultApi {
  FakeVaultApi({this.failOn = const {}});

  /// e.g. {'health-profile'} → that write returns a VaultError.
  Set<String> failOn;

  Map<String, dynamic>? profile;
  final List<String> allergies = [];
  final List<String> conditions = [];
  final List<({String name, String? dosage})> medications = [];
  int deleteCalls = 0;

  VaultWrite _r(String tag) => failOn.contains(tag)
      ? VaultError("simulated $tag failure")
      : const VaultOk();

  @override
  Future<VaultWrite> putHealthProfile({
    String? gender,
    String? activityLevel,
    double? weight,
    double? height,
    String? weightUnit,
    String? heightUnit,
    List<String> diet = const [],
  }) async {
    profile = {
      'gender': gender,
      'activity_level': activityLevel,
      'weight': weight,
      'height': height,
      'diet': diet,
    };
    return _r('health-profile');
  }

  @override
  Future<VaultWrite> addAllergy(String name) async {
    allergies.add(name);
    return _r('allergies');
  }

  @override
  Future<VaultWrite> addCondition(String name) async {
    conditions.add(name);
    return _r('conditions');
  }

  @override
  Future<VaultWrite> addMedication(String name,
      {String? dosage, DateTime? activeFrom}) async {
    medications.add((name: name, dosage: dosage));
    return _r('medications');
  }

  @override
  Future<VaultWrite> deleteMedication(String id) async {
    medications.removeWhere((m) => m.name == id);
    return _r('medications');
  }

  @override
  Future<HealthProfileData?> fetchHealthProfile() async => profile == null
      ? null
      : HealthProfileData(
          gender: profile!['gender'] as String?,
          activityLevel: profile!['activity_level'] as String?,
          weight: (profile!['weight'] as num?)?.toDouble(),
          height: (profile!['height'] as num?)?.toDouble(),
          diet: ((profile!['diet'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList(),
        );

  /// name -> mapping; empty by default. Tests set entries to exercise the UI.
  Map<String, MedMapping> medMapping = {};

  @override
  Future<Map<String, MedMapping>> fetchMedicationMapping() async => medMapping;

  @override
  Future<MedicationsResult> fetchMedications() async => MedicationsLoaded([
        for (final m in medications)
          Medication(id: m.name, name: m.name, dosage: m.dosage),
      ]);

  @override
  Future<VaultWrite> deleteAccount() async {
    deleteCalls++;
    return _r('account');
  }
}

class FakeDrugsApi implements DrugsApi {
  FakeDrugsApi({this.hits = const [], this.error});

  /// Returned (filtered by a naive contains match) for any query ≥ 2 chars.
  List<DrugHit> hits;
  String? error;
  final List<String> queries = [];

  @override
  Future<DrugSearchResult> search(String query, {int limit = 20}) async {
    final q = query.trim();
    queries.add(q);
    if (q.replaceAll(RegExp(r'\s'), '').length < 2) {
      return const DrugSearchHits([]);
    }
    if (error != null) return DrugSearchError(error!);
    final lc = q.toLowerCase();
    final matched = hits
        .where((d) =>
            d.name.toLowerCase().contains(lc) ||
            (d.activeIngredients ?? '').toLowerCase().contains(lc) ||
            (d.saltComposition ?? '').toLowerCase().contains(lc))
        .take(limit)
        .toList();
    return DrugSearchHits(matched);
  }
}

class FakeMeApi implements MeApi {
  FakeMeApi({String? displayName = 'Aarav'}) : _name = displayName;

  String? _name;
  final List<String> nameWrites = [];

  MeInfo get info => MeInfo(displayName: _name);

  @override
  Future<MeInfo> fetch() async => info;

  @override
  Future<String?> updateName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    nameWrites.add(trimmed);
    _name = trimmed;
    return null;
  }
}

class FakeFoodsApi implements FoodsApi {
  FakeFoodsApi({this.hits = const [], this.error});

  List<FoodHit> hits;
  String? error;
  final List<String> queries = [];

  @override
  Future<FoodSearchResult> search(String query, {int limit = 20}) async {
    final q = query.trim();
    queries.add(q);
    if (q.replaceAll(RegExp(r'\s'), '').length < 2) {
      return const FoodSearchHits([]);
    }
    if (error != null) return FoodSearchError(error!);
    final lc = q.toLowerCase();
    return FoodSearchHits(hits
        .where((f) =>
            f.name.toLowerCase().contains(lc) ||
            (f.brand ?? '').toLowerCase().contains(lc))
        .take(limit)
        .toList());
  }
}

class FakeLifestyleApi implements LifestyleApi {
  FakeLifestyleApi([this.profile]);
  LifestyleProfile? profile;
  final List<LifestyleProfile> writes = [];

  @override
  Future<LifestyleProfile?> fetch() async => profile;

  @override
  Future<String?> put(LifestyleProfile p) async {
    writes.add(p);
    profile = p;
    return null;
  }
}

class FakeFitApi implements FitApi {
  FakeFitApi([this.result = const FitFailed('no fit in test')]);
  FitResult result;
  @override
  Future<FitResult> fetch() async => result;
}

/// Overrides that give a test the whole wired app with no network.
List<Override> fakeBackendOverrides({
  FakeAuthApi? auth,
  FakeVaultApi? vault,
  FakeMeApi? me,
  FakeDrugsApi? drugs,
  FakeFoodsApi? foods,
  FakeLifestyleApi? lifestyle,
  FakeFitApi? fit,
  TrendsResult? trends,
  NudgesResult? nudges,
  HistoryResult? history,
}) {
  final v = vault ?? FakeVaultApi();
  final m = me ?? FakeMeApi();
  return [
    authApiProvider.overrideWithValue(auth ?? FakeAuthApi()),
    vaultApiProvider.overrideWithValue(v),
    meApiProvider.overrideWithValue(m),
    drugsApiProvider.overrideWithValue(drugs ?? FakeDrugsApi()),
    foodsApiProvider.overrideWithValue(foods ?? FakeFoodsApi()),
    lifestyleApiProvider.overrideWithValue(lifestyle ?? FakeLifestyleApi()),
    fitApiProvider.overrideWithValue(fit ?? FakeFitApi()),
    trendsProvider.overrideWith(
        (ref) async => trends ?? const TrendsFailed('offline in test')),
    nudgesProvider.overrideWith(
        (ref) async => nudges ?? const NudgesFailed('offline in test')),
    historyPageProvider.overrideWith(
        (ref) async => history ?? const HistoryFailed('offline in test')),
    medicationsProvider.overrideWith((ref) async => v.fetchMedications()),
  ];
}

/// A non-empty weekly Trends payload (6 buckets) — tall enough for the Trends
/// screen to actually scroll in tests that check scroll persistence.
TrendsLoaded sampleWeeklyTrends() => TrendsLoaded(Trends(
      timezone: 'UTC',
      totalScans: 24,
      dietHealthScore: 71,
      deltaSevenDay: 4,
      trend: 'improving',
      weekly: [
        for (var i = 0; i < 6; i++)
          TrendBucket(
            periodStart: DateTime(2026, 7, 6 + i * 7),
            label: 'W${i + 1}',
            scans: 4,
            avgScore: 60.0 + i * 3,
            medianScore: 62.0 + i * 3,
            minScore: 40,
            maxScore: 90,
            safe: 2,
            caution: 1,
            avoid: 1,
            dietHealthScore: 60 + i * 2,
          ),
      ],
    ));

/// A HistoryLoaded page with [n] rows — for tests that need a scrollable list.
HistoryLoaded sampleHistory([int n = 20]) => HistoryLoaded(HistoryPage(
      items: [
        for (var i = 0; i < n; i++)
          ScanHistoryEntry(
            id: 'h$i',
            productName: 'Scanned item $i',
            score: 40 + (i % 5) * 12,
            tier: i.isEven ? 'caution' : 'safe',
            scannedAt: DateTime(2026, 8, 20).subtract(Duration(hours: i * 6)),
          ),
      ],
      total: n,
      limit: n,
      offset: 0,
      hasMore: false,
    ));
