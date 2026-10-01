import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/features/rides/domain/ride_formatters.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

Map<String, dynamic> rideJson({
  String status = 'DRIVER_ARRIVED',
  Map<String, dynamic>? extra,
}) => {
  'id': '66f0c0ffee0000000000abcd',
  'rideCode': 'TR7K2M9QXA',
  'status': status,
  'rideType': 'AUTO',
  'vehicleType': 'AUTO',
  'pickup': {
    'address': 'Prem Mandir, Vrindavan',
    'latitude': 27.5714,
    'longitude': 77.6716,
  },
  'destination': {
    'address': 'Banke Bihari Temple, Vrindavan',
    'latitude': 27.5806,
    'longitude': 77.7006,
  },
  'distanceMeters': 3048,
  'durationSeconds': 499,
  'routeProvider': 'HAVERSINE',
  'fare': {
    'currency': 'INR',
    'baseFare': 30,
    'perKmRate': 10,
    'perMinuteRate': 1.5,
    'minimumFare': 40,
    'distanceCharge': 30.48,
    'timeCharge': 12.48,
    'subtotal': 72.96,
    'minimumFareApplied': false,
    'estimatedFare': 73,
  },
  'requestedAt': '2026-09-23T04:00:00.000Z',
  ...?extra,
};

void main() {
  group('Ride.fromJson', () {
    test('parses the customer view with driver and OTP', () {
      final ride = Ride.fromJson(
        rideJson(
          extra: {
            'driver': {
              'name': 'Rahul Kumar',
              'phone': '+919812345678',
              'ratingAverage': 4.8,
              'totalRides': 120,
              'vehicle': {
                'vehicleType': 'AUTO',
                'registrationNumber': 'UP85AA0001',
                'make': 'Bajaj',
                'color': 'Green',
              },
            },
            'otp': {'code': '0421', 'expiresAt': '2026-09-23T04:20:00.000Z'},
          },
        ),
      );
      expect(ride.status, RideStatus.driverArrived);
      expect(ride.rideType, RideTypeCode.auto);
      expect(ride.fare.estimatedFare, 73);
      expect(ride.fare.payable, 73);
      expect(ride.driver?.vehicle?.description, 'Green Bajaj');
      expect(ride.otp?.code, '0421');
      expect(ride.customer, isNull);
    });

    test('parses the driver view without an OTP', () {
      final ride = Ride.fromJson(
        rideJson(
          status: 'DRIVER_ASSIGNED',
          extra: {
            'customer': {'name': 'Sachin'},
            'assignmentExpiresAt': '2026-09-23T04:00:30.000Z',
            'pickupDistanceMeters': 612,
          },
        ),
      );
      expect(ride.customer?.name, 'Sachin');
      expect(ride.customer?.phone, isNull);
      expect(ride.pickupDistanceMeters, 612);
      expect(ride.otp, isNull);
    });

    test('prefers the final fare once completed', () {
      final json = rideJson(status: 'COMPLETED');
      (json['fare'] as Map<String, dynamic>)['finalFare'] = 75;
      expect(Ride.fromJson(json).fare.payable, 75);
    });
  });

  group('RideStatus', () {
    test('knows terminal and cancellable states', () {
      expect(RideStatus.completed.isTerminal, isTrue);
      expect(RideStatus.noDriverAvailable.isTerminal, isTrue);
      expect(RideStatus.rideStarted.isTerminal, isFalse);
      expect(RideStatus.driverArrived.customerCanCancel, isTrue);
      expect(RideStatus.rideStarted.customerCanCancel, isFalse);
      expect(RideStatus.driverAssigned.driverCanCancel, isFalse);
    });

    test('round-trips wire names', () {
      for (final status in RideStatus.values) {
        expect(RideStatus.fromWire(status.wireName), status);
      }
    });
  });

  group('RideFormat', () {
    test('formats money, distance and duration', () {
      expect(RideFormat.money(120), '₹120');
      expect(RideFormat.money(22.5), '₹22.50');
      expect(RideFormat.distance(845), '850 m');
      expect(RideFormat.distance(3048), '3.0 km');
      expect(RideFormat.duration(20), '1 min');
      expect(RideFormat.duration(3900), '1 h 5 min');
    });
  });
}
