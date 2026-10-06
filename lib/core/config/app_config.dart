import 'package:flutter/foundation.dart';

enum AppEnvironment { development, production }

/// Build-time configuration, supplied via `--dart-define` (or
/// `--dart-define-from-file=env/<name>.json`). Nothing here is read at runtime
/// from the device, so a release build cannot be pointed at a different API.
@immutable
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiOrigin,
    this.apiVersion = 'v1',
  });

  factory AppConfig.fromEnvironment() {
    const envName = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    const override = String.fromEnvironment('API_BASE_URL');
    final environment = AppEnvironment.values.firstWhere(
      (value) => value.name == envName,
      orElse: () => AppEnvironment.development,
    );
    return AppConfig(
      environment: environment,
      apiOrigin: override.isNotEmpty
          ? _stripTrailingSlash(override)
          : defaultLocalOrigin(defaultTargetPlatform, isWeb: kIsWeb),
    );
  }

  static const int localApiPort = 5100;

  final AppEnvironment environment;

  /// Scheme + host + port of the Tirvona Rides API, without the `/api` path.
  final String apiOrigin;
  final String apiVersion;

  String get apiBaseUrl => '$apiOrigin/api/$apiVersion';

  /// Socket.IO namespace of the realtime gateway (same host as the API).
  String get realtimeUrl => '$apiOrigin/realtime';

  // Maps are Google Maps SDK for Android; its key is a build-time Android
  // manifest value (android/secrets.properties), not a Dart define.

  // Public legal pages served by the API; the same URLs go in the Play
  // Console (privacy policy and account deletion).
  String get privacyPolicyUrl => '$apiBaseUrl/legal/privacy';
  String get termsUrl => '$apiBaseUrl/legal/terms';
  String get deleteAccountUrl => '$apiBaseUrl/legal/delete-account';

  bool get isProduction => environment == AppEnvironment.production;

  /// The Android emulator reaches the host machine via 10.0.2.2; iOS
  /// simulators, desktop and web share the host's loopback. Physical devices
  /// must pass `API_BASE_URL=http://<PC-LAN-IP>:5100`.
  static String defaultLocalOrigin(
    TargetPlatform platform, {
    bool isWeb = false,
  }) {
    final host = !isWeb && platform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
    return 'http://$host:$localApiPort';
  }

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
