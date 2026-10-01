import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/location/driver_location_service.dart';
import '../../../../core/location/location_tracking_policy.dart';
import '../../../../core/realtime/realtime_models.dart';
import '../../../../core/realtime/realtime_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/ride_formatters.dart';
import '../../domain/ride_models.dart';

/// Explains a missing location permission and offers the one action that
/// can fix it (ask again, or open the right settings page).
Future<void> showLocationAccessDialog(
  BuildContext context,
  WidgetRef ref,
  LocationAccess access,
) async {
  final service = ref.read(driverLocationServiceProvider.notifier);
  final (String title, String body, String action) = switch (access) {
    LocationAccess.serviceDisabled => (
      'Turn on location',
      'Your phone’s location (GPS) is switched off. Riders can only be '
          'matched with drivers whose location is known.',
      'Open location settings',
    ),
    LocationAccess.deniedForever => (
      'Allow location access',
      'Tirvona Rides needs your location while you are online so riders '
          'can be matched with you and see you arrive. Enable it in '
          'Settings → Permissions → Location.',
      'Open settings',
    ),
    _ => (
      'Allow location access',
      'While you are online, Tirvona Rides shares your location with the '
          'rider you are serving and uses it to send you nearby requests. It '
          'stops when you go offline.',
      'Allow',
    ),
  };

  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.location_off, color: AppColors.bhagwa),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  if (proceed != true) return;
  if (access == LocationAccess.denied) {
    await service.checkAccess(request: true);
    await service.retry();
  } else {
    // Streaming restarts on return from Settings (see DriverLocationService).
    await service.openSettings();
  }
}

/// Live status of the driver's GPS and connection: what riders and matching
/// currently know about this driver, and how to fix it when something is off.
class LocationStatusCard extends ConsumerWidget {
  const LocationStatusCard({super.key, required this.dashboard});

  final DriverDashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(driverLocationServiceProvider);
    final connection = ref.watch(realtimeStatusProvider).value;
    final online = dashboard.isOnline;

    final (
      IconData icon,
      Color color,
      String title,
      String subtitle,
    ) = switch (location.access) {
      LocationAccess.serviceDisabled => (
        Icons.location_disabled,
        AppColors.error,
        'Location is off',
        'Turn on GPS to receive ride requests.',
      ),
      LocationAccess.denied || LocationAccess.deniedForever => (
        Icons.location_off,
        AppColors.error,
        'Location permission needed',
        'Allow location access to go online.',
      ),
      _ when !online => (
        Icons.location_searching,
        AppColors.onSurfaceVariant,
        'Location sharing is off',
        'It starts automatically when you go online.',
      ),
      _ when connection != RealtimeStatus.connected => (
        Icons.cloud_off,
        AppColors.warning,
        'Reconnecting…',
        'Your location will be sent as soon as you are back online.',
      ),
      _ when location.weakSignal => (
        Icons.gps_not_fixed,
        AppColors.warning,
        'Weak GPS signal',
        'Move to open sky so riders can find you.',
      ),
      _ when location.streaming => (
        Icons.gps_fixed,
        AppColors.success,
        _modeLabel(location.mode),
        _lastSentLabel(location.lastSentAt, location.lastFix?.accuracy),
      ),
      _ => (
        Icons.gps_not_fixed,
        AppColors.warning,
        'Starting GPS…',
        'Getting your position.',
      ),
    };

    final needsAction =
        location.access == LocationAccess.denied ||
        location.access == LocationAccess.deniedForever ||
        location.access == LocationAccess.serviceDisabled;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: needsAction
            ? TextButton(
                onPressed: () => unawaited(
                  showLocationAccessDialog(context, ref, location.access),
                ),
                child: const Text('Fix'),
              )
            : null,
      ),
    );
  }

  static String _modeLabel(LocationTrackingMode mode) => switch (mode) {
    LocationTrackingMode.toPickup => 'Sharing live location with your rider',
    LocationTrackingMode.onTrip => 'Sharing live trip location',
    _ => 'Location on — visible for nearby requests',
  };

  static String _lastSentLabel(DateTime? sentAt, double? accuracy) {
    if (sentAt == null) return 'Waiting for the first position…';
    final accuracyText = accuracy == null ? '' : ' · ±${accuracy.round()} m';
    return 'Updated ${RideFormat.time(sentAt)}$accuracyText';
  }
}
