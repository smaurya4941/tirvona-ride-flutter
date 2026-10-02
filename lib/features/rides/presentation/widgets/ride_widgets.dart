import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/realtime/realtime_models.dart';
import '../../../../core/realtime/realtime_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/ride_formatters.dart';
import '../../domain/ride_models.dart';

/// Icon for a ride type. [iconKey] is the server's icon key (bike, auto,
/// e_rickshaw, cab, cab_xl, premium) and wins when known; otherwise the code
/// decides, so admin-created products still get a sensible icon.
IconData rideTypeIcon(RideTypeCode type, {String? iconKey}) {
  switch (iconKey) {
    case 'bike':
      return Icons.two_wheeler;
    case 'auto':
    case 'e_rickshaw':
      return Icons.electric_rickshaw;
    case 'cab':
      return Icons.directions_car;
    case 'cab_xl':
      return Icons.airport_shuttle;
    case 'premium':
      return Icons.local_taxi;
  }
  final code = type.wireName;
  if (code.contains('BIKE')) return Icons.two_wheeler;
  if (code.contains('AUTO') || code.contains('RICKSHAW')) {
    return Icons.electric_rickshaw;
  }
  return Icons.directions_car;
}

/// An error whose message is written for the user (not a server error).
class UserFacingError implements Exception {
  const UserFacingError(this.message);

  final String message;

  @override
  String toString() => message;
}

String errorMessage(Object error) => switch (error) {
  ApiException(:final message) => message,
  UserFacingError(:final message) => message,
  _ => 'Something went wrong. Please try again.',
};

void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(errorMessage(error)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

({Color background, Color foreground}) _statusColors(RideStatus status) =>
    switch (status) {
      RideStatus.searching || RideStatus.driverAssigned => (
        background: const Color(0xFFE0F2FE),
        foreground: const Color(0xFF075985),
      ),
      RideStatus.driverAccepted || RideStatus.driverArrived => (
        background: const Color(0xFFFEF3C7),
        foreground: const Color(0xFF92400E),
      ),
      RideStatus.rideStarted => (
        background: AppColors.bhagwaLight,
        foreground: AppColors.bhagwaDark,
      ),
      RideStatus.completed => (
        background: const Color(0xFFDCFCE7),
        foreground: const Color(0xFF166534),
      ),
      RideStatus.cancelled => (
        background: const Color(0xFFE2E8F0),
        foreground: const Color(0xFF334155),
      ),
      RideStatus.noDriverAvailable => (
        background: const Color(0xFFFEE2E2),
        foreground: const Color(0xFF991B1B),
      ),
    };

class RideStatusChip extends StatelessWidget {
  const RideStatusChip({super.key, required this.status});

  final RideStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.foreground.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: colors.foreground,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pickup → destination with the classic green/orange dots.
class RouteSummary extends StatelessWidget {
  const RouteSummary({
    super.key,
    required this.pickup,
    required this.destination,
    this.dense = false,
  });

  final Place pickup;
  final Place destination;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    Widget row(Color color, String label, Place place) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(Icons.circle, size: 12, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!dense)
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              Text(
                place.title,
                maxLines: dense ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (!dense && place.name != null)
                Text(
                  place.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return Column(
      children: [
        row(AppColors.success, 'Pickup', pickup),
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 2,
              height: dense ? 10 : 18,
              color: AppColors.outlineVariant,
            ),
          ),
        ),
        row(AppColors.bhagwa, 'Destination', destination),
      ],
    );
  }
}

class FareBreakdownCard extends StatelessWidget {
  const FareBreakdownCard({
    super.key,
    required this.fare,
    required this.distanceMeters,
    required this.durationSeconds,
    this.title = 'Fare breakdown',
  });

  final FareBreakdown fare;
  final int distanceMeters;
  final int durationSeconds;
  final String title;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                fontSize: strong ? 17 : 14,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              fontSize: strong ? 17 : 14,
            ),
          ),
        ],
      ),
    );

    // Once completed, the frozen final bill (actual trip) replaces the
    // booking-time estimate components.
    final bill = fare.finalBill;
    final distance = bill?.distanceMeters ?? distanceMeters;
    final duration = bill?.durationSeconds ?? durationSeconds;
    final minimumApplied = bill?.minimumFareApplied ?? fare.minimumFareApplied;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (bill != null &&
                (bill.distanceMeasured || bill.durationMeasured)) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.route_outlined,
                    size: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      bill.distanceMeasured
                          ? 'Priced on your actual trip'
                          : 'Priced on your actual trip time and the booked route',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            line('Base fare', RideFormat.money(bill?.baseFare ?? fare.baseFare)),
            line(
              'Distance (${RideFormat.distance(distance)} × '
              '${RideFormat.money(fare.perKmRate)}/km)',
              RideFormat.money(bill?.distanceCharge ?? fare.distanceCharge),
            ),
            line(
              'Time (${RideFormat.duration(duration)} × '
              '${RideFormat.money(fare.perMinuteRate)}/min)',
              RideFormat.money(bill?.timeCharge ?? fare.timeCharge),
            ),
            if (bill != null && bill.capApplied)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Capped at 1.5 × your estimate of '
                  '${RideFormat.money(fare.estimatedFare)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (minimumApplied)
              line('Minimum fare applies', RideFormat.money(fare.minimumFare)),
            const Divider(height: 24),
            if (fare.finalFare != null)
              line(
                'Final fare',
                RideFormat.money(fare.finalFare!),
                strong: true,
              )
            else
              line(
                'Estimated fare',
                RideFormat.money(fare.estimatedFare),
                strong: true,
              ),
            if (fare.hasDiscount) ...[
              line('Promo discount', '− ${RideFormat.money(fare.discount!)}'),
              line('You pay', RideFormat.money(fare.payable), strong: true),
            ],
            if (!minimumApplied)
              Text(
                'Minimum fare ${RideFormat.money(fare.minimumFare)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small icon + label + value tile used for distance/duration/fare rows.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppColors.bhagwa),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin banner shown over live screens while the realtime connection is
/// down. The screen keeps showing the last known state; everything re-syncs
/// from the server the moment the connection is back.
class ReconnectingBanner extends ConsumerWidget {
  const ReconnectingBanner({
    super.key,
    this.message = 'Reconnecting… showing the last update',
  });

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeStatusProvider).value;
    final offline =
        status == RealtimeStatus.connecting ||
        status == RealtimeStatus.reconnecting;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: !offline
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              color: AppColors.warning.withValues(alpha: 0.18),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(message, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
    );
  }
}
