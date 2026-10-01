import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/core/config/app_config.dart';

void main() {
  group('AppConfig.defaultLocalOrigin', () {
    test('uses the emulator host alias on Android', () {
      expect(
        AppConfig.defaultLocalOrigin(TargetPlatform.android),
        'http://10.0.2.2:5100',
      );
    });

    test('uses localhost on iOS and desktop', () {
      expect(
        AppConfig.defaultLocalOrigin(TargetPlatform.iOS),
        'http://localhost:5100',
      );
      expect(
        AppConfig.defaultLocalOrigin(TargetPlatform.windows),
        'http://localhost:5100',
      );
    });

    test('uses localhost on web even when the browser runs on Android', () {
      expect(
        AppConfig.defaultLocalOrigin(TargetPlatform.android, isWeb: true),
        'http://localhost:5100',
      );
    });
  });

  test('apiBaseUrl appends the versioned API path', () {
    const config = AppConfig(
      environment: AppEnvironment.development,
      apiOrigin: 'http://192.168.1.10:5100',
    );
    expect(config.apiBaseUrl, 'http://192.168.1.10:5100/api/v1');
    expect(config.isProduction, isFalse);
  });
}
