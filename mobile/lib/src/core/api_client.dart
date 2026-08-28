import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Base URL of the FastAPI backend.
///
/// - Android emulator reaches the host machine at 10.0.2.2
/// - iOS simulator / web / desktop use localhost
/// Override at build time: --dart-define=API_BASE_URL=https://...
String get apiBaseUrl {
  const fromEnv = String.fromEnvironment('API_BASE_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000';
  return 'http://localhost:8000';
}

/// The current access token (JWT from the OTP flow). Null until sign-in wires
/// it in; [dioProvider] attaches it as a Bearer header when present.
class AuthToken extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? token) => state = (token == null || token.isEmpty) ? null : token;
  void clear() => state = null;
}

final authTokenProvider = NotifierProvider<AuthToken, String?>(AuthToken.new);

/// Dio bound to the versioned API (`/api/v1/...`), with the auth token attached.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: '$apiBaseUrl/api/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(authTokenProvider);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );
  return dio;
});

/// Result of a `GET /health` call against the backend.
class HealthResult {
  const HealthResult({
    required this.reachable,
    required this.httpStatus,
    required this.body,
  });

  final bool reachable;
  final int? httpStatus;
  final Map<String, dynamic> body;

  bool get dbConnected => body['db'] == 'connected';

  @override
  String toString() =>
      reachable ? 'HTTP $httpStatus  $body' : 'unreachable ($body)';
}

/// One real `GET {apiBaseUrl}/health` (liveness + DB readiness).
/// Returns a [HealthResult] instead of throwing so callers can render failures.
Future<HealthResult> fetchHealth({Dio? client}) async {
  final dio = client ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        validateStatus: (_) => true, // 503 is a valid, informative response here
      ));
  try {
    final res = await dio.getUri<Map<String, dynamic>>(
      Uri.parse('$apiBaseUrl/health'),
    );
    return HealthResult(
      reachable: true,
      httpStatus: res.statusCode,
      body: res.data ?? const {},
    );
  } on DioException catch (e) {
    return HealthResult(
      reachable: false,
      httpStatus: e.response?.statusCode,
      body: {'error': e.message ?? e.type.name},
    );
  }
}

/// Drives the HomeScreen checkpoint card.
final healthCheckProvider =
    FutureProvider.autoDispose<HealthResult>((ref) => fetchHealth());
