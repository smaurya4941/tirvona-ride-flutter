import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage.dart';
import 'api_client.dart';
import 'api_endpoints.dart';

/// Exchanges the stored refresh token for a new token pair.
///
/// Single-flight: refresh tokens are single-use on the server (rotation), so
/// two concurrent refreshes — an HTTP 401 and a socket reconnect racing —
/// would revoke each other. Every caller shares the one in-flight request.
class TokenRefresher {
  TokenRefresher({required this._storage, required this._refreshDio});

  final SecureStorage _storage;

  /// Must not carry the auth interceptor, so a failed refresh cannot recurse.
  final Dio _refreshDio;

  Future<String?>? _inFlight;

  /// The new access token; `null` when the session is gone for good (no
  /// refresh token, or the server rejected it — tokens are then cleared).
  /// Network failures are rethrown: they say nothing about the session.
  Future<String?> refresh() =>
      _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<String?> _refresh() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) return null;
    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        ApiEndpoints.authRefresh,
        data: {'refreshToken': refreshToken},
      );
      final data = response.data!['data'] as Map<String, dynamic>;
      final accessToken = data['accessToken'] as String;
      await _storage.saveTokens(
        accessToken: accessToken,
        refreshToken: data['refreshToken'] as String,
      );
      return accessToken;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        await _storage.clearTokens();
        return null;
      }
      rethrow;
    }
  }
}

final tokenRefresherProvider = Provider<TokenRefresher>(
  (ref) => TokenRefresher(
    storage: ref.watch(secureStorageProvider),
    refreshDio: ref.watch(refreshDioProvider),
  ),
);
