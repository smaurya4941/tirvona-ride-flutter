import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The alert sounds bundled with the app (android/app/src/main/res/raw and
/// ios/Runner). Android plays a channel's sound and can't change it later,
/// so every sound owns a channel. The ids match the API
/// (notification-types.ts, PUSH_CHANNEL_IDS) and MainActivity.kt.
enum AlertSound {
  /// A new ride offer for a driver.
  rideRequest(
    sound: 'ride_request',
    channelId: 'tirvona_ride_requests_v2',
    channelName: 'New ride requests',
    channelDescription: 'A rider is asking for a ride',
  ),

  /// Ride progress, payments and account notices.
  rideUpdate(
    sound: 'ride_update',
    channelId: 'tirvona_rides_v3',
    channelName: 'Ride updates',
    channelDescription: 'Driver updates, payments and account notices',
  ),

  /// Safety alerts.
  sosAlert(
    sound: 'sos_alert',
    channelId: 'tirvona_sos_v2',
    channelName: 'Safety alerts',
    channelDescription: 'SOS and safety alerts',
  ),

  /// The notice to the person who pressed SOS: no sound and no vibration, so
  /// nobody else in the vehicle can tell an alert was raised.
  silent(
    sound: 'silent',
    channelId: 'tirvona_sos_silent_v1',
    channelName: 'Your SOS alert',
    channelDescription: 'Silent confirmation of an SOS you raised',
  );

  const AlertSound({
    required this.sound,
    required this.channelId,
    required this.channelName,
    required this.channelDescription,
  });

  final String sound;
  final String channelId;
  final String channelName;
  final String channelDescription;

  bool get isSilent => this == AlertSound.silent;

  RawResourceAndroidNotificationSound? get androidSound =>
      isSilent ? null : RawResourceAndroidNotificationSound(sound);

  AndroidNotificationChannel get channel => AndroidNotificationChannel(
    channelId,
    channelName,
    description: channelDescription,
    importance: Importance.max,
    enableVibration: !isSilent,
    playSound: !isSilent,
    sound: androidSound,
  );

  /// The sound a push asked for (the `sound` data key), else the one its
  /// type implies, else the plain chime.
  static AlertSound fromPush(Map<String, dynamic> data) {
    final requested = '${data['sound'] ?? ''}';
    for (final value in values) {
      if (value.sound == requested) return value;
    }
    final type = '${data['type'] ?? ''}';
    if (type == 'RIDE_REQUEST') return rideRequest;
    if (type.startsWith('SOS')) return sosAlert;
    return rideUpdate;
  }
}
