// networkErrorMessage — a Dio failure (OFF / backend slow, rate-limited, or
// unreachable mid-scan) becomes a short honest line; the UI never spins forever
// because dioProvider sets connect/receive timeouts that force the catch.

import 'dart:typed_data';

import 'package:carecart/src/core/product_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _e(DioExceptionType type) =>
    DioException(requestOptions: RequestOptions(path: '/x'), type: type);

void main() {
  test('a hard "no connection" is called that', () {
    expect(
      networkErrorMessage(_e(DioExceptionType.connectionError), fallback: 'x'),
      'No connection to the server.',
    );
  });

  test('every timeout flavour maps to the "taking too long" line', () {
    for (final t in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ]) {
      expect(
        networkErrorMessage(_e(t), fallback: 'x'),
        'The server is taking too long to respond. Check your connection and try again.',
        reason: '$t',
      );
    }
  });

  test('anything else uses the caller fallback', () {
    expect(
      networkErrorMessage(_e(DioExceptionType.badResponse),
          fallback: "Couldn't score this product."),
      "Couldn't score this product.",
    );
  });

  test('scanVerdict surfaces the timeout line, never a spinner', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = _ThrowingAdapter(DioExceptionType.receiveTimeout);
    final r = await scanVerdict(dio, ingredients: ['salt']);
    expect(
      (r as ScanVerdictFailed).message,
      'The server is taking too long to respond. Check your connection and try again.',
    );
  });
}

class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.type);
  final DioExceptionType type;
  @override
  Future<ResponseBody> fetch(
          RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancel) =>
      throw DioException(requestOptions: options, type: type);
  @override
  void close({bool force = false}) {}
}
