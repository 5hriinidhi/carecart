import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connectivity.dart';

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

/// Every network call in the app goes through this Dio. The timeouts here are
/// what guarantee the UI never spins forever — a stalled request fails with a
/// `DioException` the api helpers turn into a message (Phase 6.3).
const kConnectTimeout = Duration(seconds: 8);
const kReceiveTimeout = Duration(seconds: 12);
const kSendTimeout = Duration(seconds: 20); // uploads (label-scan multipart)

/// Builds the app's Dio: versioned base URL, the three timeouts, the Bearer
/// token, and backend-reachability tracking. Exposed so tests can build an
/// identically-behaving client with a swappable adapter.
Dio buildApiDio(Ref ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: '$apiBaseUrl/api/v1',
      connectTimeout: kConnectTimeout,
      receiveTimeout: kReceiveTimeout,
      sendTimeout: kSendTimeout,
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
      onResponse: (response, handler) {
        // any HTTP response at all means we reached the backend
        ref.read(reachabilityProvider.notifier).markOk();
        handler.next(response);
      },
      onError: (e, handler) {
        final unreachable = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;
        final n = ref.read(reachabilityProvider.notifier);
        unreachable ? n.markUnreachable() : n.markOk();
        handler.next(e);
      },
    ),
  );
  return dio;
}

/// Dio bound to the versioned API (`/api/v1/...`), with the auth token attached
/// and backend-reachability tracking.
final dioProvider = Provider<Dio>(buildApiDio);

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
        // a liveness probe should be quick — fail fast rather than hang the card
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
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
