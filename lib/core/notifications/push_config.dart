import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase Cloud Messaging settings, supplied at build time like the rest
/// of [AppConfig] (`--dart-define-from-file=env/<name>.json`). No
/// google-services.json / GoogleService-Info.plist is needed.
///
/// When they are missing the app still works: push is off and the
/// notification centre fills from the API and the realtime socket.
@immutable
class PushConfig {
  const PushConfig({
    required this.apiKey,
    required this.projectId,
    required this.messagingSenderId,
    required this.androidAppId,
    required this.iosAppId,
    required this.iosBundleId,
  });

  factory PushConfig.fromEnvironment() => const PushConfig(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    androidAppId: String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
    iosAppId: String.fromEnvironment('FIREBASE_IOS_APP_ID'),
    iosBundleId: String.fromEnvironment(
      'FIREBASE_IOS_BUNDLE_ID',
      defaultValue: 'com.tirvona.ride',
    ),
  );

  final String apiKey;
  final String projectId;
  final String messagingSenderId;
  final String androidAppId;
  final String iosAppId;
  final String iosBundleId;

  /// Firebase options for this platform, or `null` when push is not set up
  /// for it (web/desktop builds, or missing keys).
  FirebaseOptions? optionsFor(TargetPlatform platform, {bool isWeb = kIsWeb}) {
    if (isWeb ||
        apiKey.isEmpty ||
        projectId.isEmpty ||
        messagingSenderId.isEmpty) {
      return null;
    }
    return switch (platform) {
      TargetPlatform.android when androidAppId.isNotEmpty => FirebaseOptions(
        apiKey: apiKey,
        appId: androidAppId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
      ),
      TargetPlatform.iOS when iosAppId.isNotEmpty => FirebaseOptions(
        apiKey: apiKey,
        appId: iosAppId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        iosBundleId: iosBundleId,
      ),
      _ => null,
    };
  }
}
