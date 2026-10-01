import 'package:dio/dio.dart';

import '../../storage/secure_storage.dart';
import '../api_endpoints.dart';
import '../token_refresher.dart';

/// Attaches the stored access token to every request and, on a 401, tries a
/// single silent refresh-and-retry before giving up and signalling
/// [onSessionExpired] so the router can drop back to the login screen.
///
/// Refreshing goes through the shared [TokenRefresher] (single-flight, also
/// used by the realtime socket), and the retry through [retryDio] — a Dio
/// instance with no [AuthInterceptor] — so it can never recurse.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this._secureStorage,
    required this._tokenRefresher,
    required this._retryDio,
    required this._onSessionExpired,
  });

  final SecureStorage _secureStorage;
  final TokenRefresher _tokenRefresher;
  final Dio _retryDio;
  final Future<void> Function() _onSessionExpired;

  // Auth endpoints hitting 401 mean bad credentials, not an expired session
  // — refreshing wouldn't help and would just mask the real error.
  static const _skipRefreshPaths = [
    ApiEndpoints.authLogin,
    ApiEndpoints.authRegister,
    ApiEndpoints.authRefresh,
  ];

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _secureStorage.readAccessToken();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final alreadyRetried = err.requestOptions.extra['retried'] == true;
    final isUnauthorized = err.response?.statusCode == 401;
    final isSkippedPath = _skipRefreshPaths.contains(err.requestOptions.path);

    if (!isUnauthorized || isSkippedPath || alreadyRetried) {
      return handler.next(err);
    }

    final String? newAccessToken;
    try {
      newAccessToken = await _tokenRefresher.refresh();
    } on DioException {
      // Couldn't reach the server to refresh: the session may be fine.
      return handler.next(err);
    }
    if (newAccessToken == null) {
      await _onSessionExpired();
      return handler.next(err);
    }

    try {
      final retryOptions = err.requestOptions
        ..headers['Authorization'] = 'Bearer $newAccessToken'
        ..extra['retried'] = true;
      return handler.resolve(await _retryDio.fetch<dynamic>(retryOptions));
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }
}
