import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/session_controller.dart';
import '../config/app_config.dart';
import '../config/app_config_provider.dart';
import '../storage/secure_storage.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/request_id_interceptor.dart';
import 'token_refresher.dart';

Dio createDio(AppConfig config) {
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );
  dio.interceptors.add(RequestIdInterceptor());
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (line) => developer.log(line.toString(), name: 'http'),
      ),
    );
  }
  return dio;
}

/// A Dio instance with no [AuthInterceptor] attached, used only for the
/// refresh-token call itself so a failed refresh can never recurse back
/// through auth handling.
final refreshDioProvider = Provider<Dio>((ref) {
  final dio = createDio(ref.watch(appConfigProvider));
  ref.onDispose(dio.close);
  return dio;
});

/// The Dio instance every repository should use. Attaches the stored access
/// token to each request and transparently refreshes it once on a 401.
final dioProvider = Provider<Dio>((ref) {
  final dio = createDio(ref.watch(appConfigProvider));
  dio.interceptors.add(
    AuthInterceptor(
      secureStorage: ref.watch(secureStorageProvider),
      tokenRefresher: ref.watch(tokenRefresherProvider),
      retryDio: ref.watch(refreshDioProvider),
      onSessionExpired: () =>
          ref.read(sessionControllerProvider.notifier).handleSessionExpired(),
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});
