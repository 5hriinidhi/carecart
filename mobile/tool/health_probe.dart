// Phase 1 -> 2 wire check, part A: one real HTTP GET to the backend's /health,
// using package:dio (the same HTTP client the app uses). Runs on the plain
// Dart VM - no Flutter engine - so it stays fast and non-flaky.
//
//   dart run tool/health_probe.dart              (backend on :8000)
//   dart run tool/health_probe.dart http://10.0.2.2:8000
//
// Exit 0 = wire is live (HTTP 200 + {"db":"connected"}). Exit 1 = not.

import 'dart:io';

import 'package:dio/dio.dart';

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty ? args.first : 'http://localhost:8000';
  final url = '$base/health';
  stdout.writeln('GET $url');

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    validateStatus: (_) => true,
  ));

  try {
    final res = await dio.get<Map<String, dynamic>>(url);
    final body = res.data ?? const {};
    stdout.writeln('  HTTP status : ${res.statusCode}');
    stdout.writeln('  body        : $body');
    final ok = res.statusCode == 200 && body['db'] == 'connected';
    stdout.writeln(ok ? 'WIRE CHECK PASSED' : 'WIRE CHECK FAILED');
    exit(ok ? 0 : 1);
  } on DioException catch (e) {
    stdout.writeln('  unreachable : ${e.message ?? e.type.name}');
    stdout.writeln('WIRE CHECK FAILED');
    exit(1);
  }
}
