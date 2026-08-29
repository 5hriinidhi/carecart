import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'product_api.dart' show networkErrorMessage;

/// The token pair from `POST /api/v1/auth/verify-otp`.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.isNewUser,
  });

  final String accessToken;
  final String refreshToken;

  /// True when verify-otp just created the account — the client runs the
  /// profile-setup steps rather than jumping straight to the app.
  final bool isNewUser;

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
        accessToken: j['access_token'] as String? ?? '',
        refreshToken: j['refresh_token'] as String? ?? '',
        isNewUser: j['is_new_user'] as bool? ?? false,
      );
}

/// Result of `POST /api/v1/auth/request-otp`.
sealed class RequestOtpResult {
  const RequestOtpResult();
}

class OtpRequested extends RequestOtpResult {
  const OtpRequested({this.devCode, required this.expiresIn});

  /// The code itself — populated ONLY by a development / test backend so local
  /// and CI runs work without an SMS provider. Always null in production.
  final String? devCode;
  final int expiresIn;
}

class OtpRequestFailed extends RequestOtpResult {
  const OtpRequestFailed(this.message, {this.retryAfterSeconds});
  final String message;
  final int? retryAfterSeconds;
}

/// Result of `POST /api/v1/auth/verify-otp`.
sealed class VerifyOtpResult {
  const VerifyOtpResult();
}

class OtpVerified extends VerifyOtpResult {
  const OtpVerified(this.session);
  final AuthSession session;
}

class OtpVerifyFailed extends VerifyOtpResult {
  const OtpVerifyFailed(this.message);
  final String message;
}

/// `POST /api/v1/auth/request-otp`. Never throws.
Future<RequestOtpResult> requestOtpApi(Dio dio, String phone) async {
  try {
    final res = await dio.post<Map<String, dynamic>>(
      '/auth/request-otp',
      data: {'phone': phone},
      options: Options(validateStatus: (s) => s != null),
    );
    final status = res.statusCode ?? 0;
    if (status == 200) {
      final body = res.data ?? const {};
      return OtpRequested(
        devCode: body['dev_code'] as String?,
        expiresIn: (body['expires_in'] as num?)?.toInt() ?? 0,
      );
    }
    if (status == 429) {
      final retry =
          int.tryParse(res.headers.value('retry-after') ?? '') ?? 60;
      return OtpRequestFailed(
        _detail(res.data) ??
            'Too many code requests for this number. Try again shortly.',
        retryAfterSeconds: retry,
      );
    }
    return OtpRequestFailed(_detail(res.data) ??
        (status == 422
            ? 'Enter a valid phone number.'
            : "Couldn't send a code ($status)."));
  } on DioException catch (e) {
    return OtpRequestFailed(
        networkErrorMessage(e, fallback: "Couldn't reach the server."));
  }
}

/// `POST /api/v1/auth/verify-otp`. Never throws.
Future<VerifyOtpResult> verifyOtpCodeApi(Dio dio, String phone, String code) async {
  try {
    final res = await dio.post<Map<String, dynamic>>(
      '/auth/verify-otp',
      data: {'phone': phone, 'code': code},
      options: Options(validateStatus: (s) => s != null),
    );
    final status = res.statusCode ?? 0;
    if (status == 200) {
      return OtpVerified(AuthSession.fromJson(res.data ?? const {}));
    }
    return OtpVerifyFailed(_detail(res.data) ??
        (status == 400
            ? 'That code is wrong or has expired. Request a new one.'
            : "Couldn't verify the code ($status)."));
  } on DioException catch (e) {
    return OtpVerifyFailed(
        networkErrorMessage(e, fallback: "Couldn't reach the server."));
  }
}

String? _detail(Object? body) {
  if (body is Map && body['detail'] is String) return body['detail'] as String;
  return null;
}

/// Injectable seam for the onboarding flow — override in tests with a fake.
class AuthApi {
  AuthApi(this._dio);
  final Dio _dio;

  Future<RequestOtpResult> requestOtp(String phone) =>
      requestOtpApi(_dio, phone);

  Future<VerifyOtpResult> verifyOtp(String phone, String code) =>
      verifyOtpCodeApi(_dio, phone, code);
}

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.read(dioProvider)));
