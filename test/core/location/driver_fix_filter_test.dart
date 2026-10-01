import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/core/location/driver_fix.dart';
import 'package:tirvona_ride/core/location/location_tracking_policy.dart';
import 'package:tirvona_ride/features/rides/application/driver_duty_binding.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

import '../../features/rides/ride_models_test.dart' show rideJson;

final _t0 = DateTime(2026, 9, 24, 10);

DriverFix _fix({
  double latitude = 27.5714,
  double longitude = 77.6716,
  double accuracy = 8,
  Duration after = Duration.zero,
}) => DriverFix(
  latitude: latitude,
  longitude: longitude,
  accuracy: accuracy,
  recordedAt: _t0.add(after),
);

void main() {
  group('DriverFixFilter', () {
    test('accepts good fixes and rejects inaccurate or stale ones', () {
      final filter = DriverFixFilter();
      expect(filter.check(_fix(), now: _t0), FixVerdict.accept);
      expect(
        filter.check(
          _fix(accuracy: 400, after: const Duration(seconds: 5)),
          now: _t0.add(const Duration(seconds: 5)),
        ),
        FixVerdict.inaccurate,
      );
      expect(
        filter.check(
          _fix(after: const Duration(seconds: 6)),
          now: _t0.add(const Duration(minutes: 2)),
        ),
        FixVerdict.stale,
      );
    });

    test('throttles bursts and drops physically impossible jumps', () {
      final filter = DriverFixFilter();
      expect(filter.check(_fix(), now: _t0), FixVerdict.accept);
      expect(
        filter.check(_fix(after: const Duration(milliseconds: 300)), now: _t0),
        FixVerdict.tooSoon,
      );
      // ~11 km in 5 s.
      expect(
        filter.check(
          _fix(latitude: 27.67, after: const Duration(seconds: 5)),
          now: _t0.add(const Duration(seconds: 5)),
        ),
        FixVerdict.implausibleJump,
      );
      // ~100 m in 10 s is ordinary driving.
      expect(
        filter.check(
          _fix(latitude: 27.5723, after: const Duration(seconds: 10)),
          now: _t0.add(const Duration(seconds: 10)),
        ),
        FixVerdict.accept,
      );
    });

    test('payload is the server contract', () {
      final payload = _fix().toPayload(rideId: 'r1');
      expect(
        payload.keys,
        containsAll([
          'latitude',
          'longitude',
          'accuracy',
          'recordedAt',
          'rideId',
        ]),
      );
      expect(payload.containsKey('heading'), isFalse);
    });
  });

  group('trackingModeFor', () {
    DriverDashboard dashboard({required bool online, String? rideStatus}) =>
        DriverDashboard.fromJson({
          'isOnline': online,
          'isAvailable': rideStatus == null,
          'currentRide': rideStatus == null
              ? null
              : rideJson(status: rideStatus),
        });

    test('follows the server duty state', () {
      expect(
        trackingModeFor(dashboard(online: false)),
        LocationTrackingMode.off,
      );
      expect(
        trackingModeFor(dashboard(online: true)),
        LocationTrackingMode.waiting,
      );
      expect(
        trackingModeFor(dashboard(online: true, rideStatus: 'DRIVER_ACCEPTED')),
        LocationTrackingMode.toPickup,
      );
      expect(
        trackingModeFor(dashboard(online: true, rideStatus: 'DRIVER_ARRIVED')),
        LocationTrackingMode.toPickup,
      );
      expect(
        trackingModeFor(dashboard(online: true, rideStatus: 'RIDE_STARTED')),
        LocationTrackingMode.onTrip,
      );
    });

    test(
      'every streaming mode heartbeats well inside the 60 s stale window',
      () {
        for (final mode in LocationTrackingMode.values) {
          final profile = LocationTrackingPolicy.profileFor(mode);
          if (profile != null) {
            expect(profile.heartbeat.inSeconds, lessThanOrEqualTo(30));
          }
        }
      },
    );
  });
}
