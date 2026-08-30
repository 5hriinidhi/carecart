import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'product_api.dart' show networkErrorMessage;

/// The signed-in user's own account info — right now just their display name,
/// so the app greets them by name instead of a hardcoded persona.
class MeInfo {
  const MeInfo({this.displayName});
  final String? displayName;

  /// First name for greetings; falls back to a friendly generic.
  String get firstName {
    final n = (displayName ?? '').trim();
    return n.isEmpty ? 'there' : n.split(RegExp(r'\s+')).first;
  }

  /// One-letter avatar.
  String get initial {
    final n = (displayName ?? '').trim();
    return n.isEmpty ? '·' : n[0].toUpperCase();
  }

  factory MeInfo.fromJson(Map<String, dynamic> j) =>
      MeInfo(displayName: j['display_name'] as String?);
}

/// The `/me` seam. A fake stands in for it in widget / state tests (see
/// `test/support/fake_backend.dart`) so nothing here needs a live server.
abstract class MeApi {
  /// `GET /me`. Never throws — returns an empty [MeInfo] on any failure so the
  /// UI just shows the generic greeting.
  Future<MeInfo> fetch();

  /// `PATCH /me` — set the display name (onboarding). Returns null on success,
  /// a short message on failure.
  Future<String?> updateName(String name);
}

class HttpMeApi implements MeApi {
  HttpMeApi(this._dio);
  final Dio _dio;

  @override
  Future<MeInfo> fetch() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/me',
        options: Options(validateStatus: (s) => s != null),
      );
      if (res.statusCode == 200) return MeInfo.fromJson(res.data ?? const {});
      return const MeInfo();
    } on DioException {
      return const MeInfo();
    }
  }

  @override
  Future<String?> updateName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null; // nothing to save
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/me',
        data: {'display_name': trimmed},
        options: Options(validateStatus: (s) => s != null),
      );
      if (res.statusCode == 200) return null;
      return "Couldn't save your name (${res.statusCode}).";
    } on DioException catch (e) {
      return networkErrorMessage(e, fallback: "Couldn't save your name.");
    }
  }
}

final meApiProvider = Provider<MeApi>((ref) => HttpMeApi(ref.read(dioProvider)));

/// Drives the home greeting + the profile sheet. Auto-disposes so it refetches
/// after sign-in / a name change (`ref.invalidate(meProvider)`).
final meProvider = FutureProvider.autoDispose<MeInfo>(
  (ref) => ref.read(meApiProvider).fetch(),
);
