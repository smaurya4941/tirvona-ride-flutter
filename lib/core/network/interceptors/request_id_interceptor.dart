import 'dart:math';

import 'package:dio/dio.dart';

/// Tags each request with an `X-Request-Id` the backend echoes into its logs
/// and error bodies, so a failure seen in the app can be found server-side.
class RequestIdInterceptor extends Interceptor {
  RequestIdInterceptor({Random? random}) : _random = random ?? Random.secure();

  static const header = 'X-Request-Id';
  final Random _random;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent(header, _generate);
    handler.next(options);
  }

  String _generate() {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    return 'app-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
