import 'dart:developer' as developer;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/config/app_config_provider.dart';
import 'core/notifications/push_config.dart';
import 'core/notifications/push_notifications.dart';
import 'features/branding/application/branding_controller.dart';
import 'features/branding/data/branding_cache.dart';
import 'features/branding/domain/branding.dart';

/// Single startup path for every build flavour. Crash reporting (Firebase
/// Crashlytics) hooks into the two error handlers below when it is added.
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log(
      'Flutter error',
      error: details.exception,
      stackTrace: details.stack,
      name: 'app',
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    developer.log(
      'Uncaught error',
      error: error,
      stackTrace: stack,
      name: 'app',
    );
    return true;
  };

  developer.log(
    'Starting ${config.environment.name} build against ${config.apiBaseUrl}',
    name: 'app',
  );

  // Push is optional per build: without Firebase keys the app runs with
  // in-app notifications only.
  final pushEnabled = await initializePush(PushConfig.fromEnvironment());

  // Admin-set logo/splash from the last run, read before the first frame so
  // the splash never flashes the bundled default first. Local disk only.
  final (brandingCache, branding) = await _openBrandingCache();

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        pushEnabledProvider.overrideWithValue(pushEnabled),
        brandingCacheProvider.overrideWithValue(brandingCache),
        initialBrandingProvider.overrideWithValue(branding),
      ],
      child: const TirvonaRideApp(),
    ),
  );
}

Future<(BrandingCache?, BrandingState)> _openBrandingCache() async {
  try {
    final cache = await BrandingCache.inAppSupport();
    final state = await cache.load().timeout(const Duration(seconds: 2));
    return (cache, state);
  } on Object catch (error) {
    developer.log('Branding cache unavailable', error: error, name: 'app');
    return (null, BrandingState.defaults);
  }
}
