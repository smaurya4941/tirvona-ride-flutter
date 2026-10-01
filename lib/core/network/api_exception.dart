import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum ApiErrorKind {
  network,
  timeout,
  server,
  client,
  unauthorized,
  cancelled,
  unknown,
}

/// The single error type repositories surface to the UI. Messages come from the
/// backend's `{ success: false, message }` envelope when one is present.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.requestId,
    this.data,
  });

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    final body = response?.data;
    final envelope = body is Map<String, dynamic>
        ? body
        : const <String, dynamic>{};
    final serverMessage = envelope['message'];
    final requestId =
        envelope['requestId'] as String? ??
        response?.headers.value('x-request-id');

    final kind = switch (error.type) {
      // No TCP connection within the connect timeout: the server was never
      // reached (wrong API_BASE_URL, other Wi-Fi, firewall) — not "slow".
      DioExceptionType.connectionTimeout => ApiErrorKind.network,
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => ApiErrorKind.timeout,
      DioExceptionType.connectionError => ApiErrorKind.network,
      DioExceptionType.cancel => ApiErrorKind.cancelled,
      DioExceptionType.badResponse => _kindForStatus(response?.statusCode),
      _ => ApiErrorKind.unknown,
    };

    return ApiException(
      kind: kind,
      statusCode: response?.statusCode,
      code: envelope['code'] as String?,
      requestId: requestId,
      data: envelope['data'],
      message: serverMessage is String && serverMessage.isNotEmpty
          ? serverMessage
          : _withServerHint(_fallbackMessage(kind), kind, error.requestOptions),
    );
  }

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? code;
  final String? requestId;
  final Object? data;

  static ApiErrorKind _kindForStatus(int? status) {
    if (status == 401 || status == 403) return ApiErrorKind.unauthorized;
    if (status != null && status >= 500) return ApiErrorKind.server;
    return ApiErrorKind.client;
  }

  /// Debug builds name the server that could not be reached, so a phone
  /// built against the wrong API_BASE_URL is obvious at a glance.
  static String _withServerHint(
    String message,
    ApiErrorKind kind,
    RequestOptions request,
  ) {
    if (!kDebugMode || request.baseUrl.isEmpty) return message;
    if (kind != ApiErrorKind.network && kind != ApiErrorKind.timeout) {
      return message;
    }
    final origin = Uri.tryParse(request.baseUrl)?.origin ?? request.baseUrl;
    return '$message\n(Server: $origin)';
  }

  static String _fallbackMessage(ApiErrorKind kind) => switch (kind) {
    ApiErrorKind.network =>
      'Cannot reach Tirvona Rides. Check your connection.',
    ApiErrorKind.timeout =>
      'The server took too long to respond. Please try again.',
    ApiErrorKind.server =>
      'Something went wrong on our side. Please try again.',
    ApiErrorKind.unauthorized =>
      'Your session has expired. Please sign in again.',
    ApiErrorKind.cancelled => 'The request was cancelled.',
    ApiErrorKind.client ||
    ApiErrorKind.unknown => 'Something went wrong. Please try again.',
  };

  @override
  String toString() =>
      'ApiException($kind, $statusCode, $message, requestId: $requestId)';
}
