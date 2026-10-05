import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/features/circuit/data/circuit_repository.dart';
import 'package:tirvona_ride/features/circuit/domain/circuit_models.dart';
import 'package:tirvona_ride/features/circuit/presentation/widgets/circuit_widgets.dart';
import 'package:tirvona_ride/features/driver/circuit/driver_circuit_panel.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

Map<String, dynamic> _stop(int order, String name, String status) => {
  'order': order,
  'placeId': 'featured:$order',
  'name': name,
  'address': '$name, Vrindavan',
  'latitude': 27.58 + order / 1000,
  'longitude': 77.69,
  'status': status,
};

/// A circuit ride as `GET /circuit-rides/:id` returns it to the driver.
Map<String, dynamic> _ride({
  String status = 'RIDE_STARTED',
  List<String> stops = const ['COMPLETED', 'ARRIVED', 'UPCOMING'],
  int current = 2,
  Map<String, dynamic>? exception,
  Map<String, dynamic>? finalBill,
  num? finalFare,
}) => {
  'id': 'ride1',
  'rideCode': 'TRCIRC0001',
  'status': status,
  'stateVersion': 7,
  'kind': 'CIRCUIT',
  'rideType': 'AUTO',
  'pickup': {'address': 'Hotel Brijwasi', 'latitude': 27.57, 'longitude': 77.67},
  'destination': {'address': 'Keshi Ghat', 'latitude': 27.585, 'longitude': 77.696},
  'distanceMeters': 4200,
  'durationSeconds': 900,
  'requestedAt': '2026-10-05T04:00:00.000Z',
  'startedAt': '2026-10-05T04:30:00.000Z',
  'fare': {
    'currency': 'INR',
    'baseFare': 600,
    'perKmRate': 15,
    'perMinuteRate': 0.83,
    'minimumFare': 600,
    'distanceCharge': 0,
    'timeCharge': 0,
    'subtotal': 600,
    'minimumFareApplied': false,
    'estimatedFare': 600,
    'finalFare': ?finalFare,
    'final': ?finalBill,
  },
  'paymentStatus': finalFare == null ? 'NOT_REQUIRED' : 'PENDING',
  'customer': {'name': 'Rahul Sharma', 'phone': '+919800000001'},
  'circuit': {
    'packageId': 'pkg1',
    'packageCode': 'CIR-001',
    'name': 'Vrindavan Spiritual Circuit',
    'city': 'Vrindavan',
    'passengers': 3,
    'stops': [
      for (final (index, name) in ['Banke Bihari', 'Nidhivan', 'Keshi Ghat'].indexed)
        _stop(index + 1, name, stops[index]),
    ],
    'currentStopOrder': current,
    'readyToComplete': current > 3,
    'pricing': {
      'basePrice': 600,
      'includedDistanceMeters': 30000,
      'includedDurationSeconds': 18000,
      'extraDistanceRatePerKm': 15,
      'extraDurationRatePerHour': 50,
    },
    'usage': {
      'distanceMeters': 17400,
      'distanceReliable': true,
      'elapsedSeconds': 8040,
      'remainingSeconds': 9960,
      'remainingDistanceMeters': 12600,
      'serverTime': '2026-10-05T06:44:00.000Z',
    },
    'projected': {
      'basePrice': 600,
      'extraKm': 0,
      'extraDistanceCharge': 0,
      'extraBlocks': 0,
      'extraDurationCharge': 0,
      'total': 600,
    },
    'exception': ?exception,
  },
};

class _FakeCircuitRepository implements CircuitRepository {
  final calls = <String>[];

  Ride _ok() => Ride.fromJson(_ride());

  @override
  Future<Ride> arriveAtStop(String rideId, int order) async {
    calls.add('arrive:$order');
    return _ok();
  }

  @override
  Future<Ride> waitAtStop(String rideId, int order) async {
    calls.add('wait:$order');
    return _ok();
  }

  @override
  Future<Ride> completeStop(String rideId, int order) async {
    calls.add('complete:$order');
    return _ok();
  }

  @override
  Future<Ride> reportStopBlocked(String rideId, int order, {String? note}) async {
    calls.add('blocked:$order');
    return _ok();
  }

  @override
  Future<Ride> completeCircuit(String rideId) async {
    calls.add('completeCircuit');
    return _ok();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('circuit ride model', () {
    test('a CIRCUIT ride carries its package, stops and usage', () {
      final ride = Ride.fromJson(_ride());
      expect(ride.isCircuit, isTrue);
      final circuit = ride.circuit!;
      expect(circuit.name, 'Vrindavan Spiritual Circuit');
      expect(circuit.stops.map((stop) => stop.status), [
        CircuitStopStatus.completed,
        CircuitStopStatus.arrived,
        CircuitStopStatus.upcoming,
      ]);
      expect(circuit.currentStop?.name, 'Nidhivan');
      expect(circuit.nextStop?.name, 'Keshi Ghat');
      expect(circuit.stopsDone, 1);
      expect(circuit.pricing.includedDurationSeconds, 18000);
      expect(circuit.hasException, isFalse);
    });

    test('a normal ride has no circuit, even if a stray field is present', () {
      final json = _ride()..['kind'] = 'NORMAL';
      expect(Ride.fromJson(json).isCircuit, isFalse);
      final legacy = _ride()..remove('kind');
      expect(Ride.fromJson(legacy).isCircuit, isFalse);
    });

    test('an open exception is surfaced', () {
      final ride = Ride.fromJson(
        _ride(exception: {'type': 'STOP_BLOCKED', 'stopOrder': 2, 'note': 'Road closed', 'reportedAt': '2026-10-05T06:40:00Z'}),
      );
      expect(ride.circuit!.exceptionStopOrder, 2);
      expect(ride.circuit!.exceptionNote, 'Road closed');
    });

    test('notices say what happened, differently for each role', () {
      final customer = CircuitNotice.fromEvent(CircuitEvents.timeWarning, {'warning': 'TIME_30_MIN'}, asDriver: false);
      final driver = CircuitNotice.fromEvent(CircuitEvents.timeWarning, {'warning': 'TIME_30_MIN'}, asDriver: true);
      expect(customer!.message, contains('30 minutes'));
      expect(customer.isWarning, isTrue);
      expect(driver!.message, 'Package time remaining: 30 minutes.');
      expect(CircuitNotice.fromEvent(CircuitEvents.nextStop, {'stopName': 'ISKCON'}, asDriver: false)!.message, 'Next stop: ISKCON');
      // Usage ticks only refresh the screen.
      expect(CircuitNotice.fromEvent(CircuitEvents.usage, {}, asDriver: false), isNull);
    });

    test('formats', () {
      expect(CircuitFormat.includedTime(18000), '5 hours');
      expect(CircuitFormat.includedTime(16200), '4.5 hours');
      expect(CircuitFormat.clock(8040), '2h 14m');
      expect(CircuitFormat.clock(-720), '−0h 12m');
      expect(CircuitFormat.km(17400), '17.4 km');
      expect(CircuitFormat.includedKm(30000), '30 km');
      expect(CircuitFormat.days([0, 1, 2, 3, 4, 5, 6]), 'Every day');
      expect(CircuitFormat.days([0, 1, 2, 3, 4]), 'Mon–Fri');
      expect(CircuitFormat.days([5, 6]), 'Sat, Sun');
    });

    test('idempotency keys are unique per booking attempt', () {
      final keys = {for (var i = 0; i < 50; i++) newIdempotencyKey()};
      expect(keys, hasLength(50));
      expect(keys.first, matches(RegExp(r'^circuit-[0-9a-f]{32}$')));
    });
  });

  group('circuit widgets', () {
    Widget host(Widget child) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

    testWidgets('timeline shows visited, current and upcoming stops', (tester) async {
      final circuit = Ride.fromJson(_ride()).circuit!;
      await tester.pumpWidget(host(CircuitStopsTimeline(stops: circuit.stops, pickup: 'Hotel Brijwasi', currentOrder: 2)));
      expect(find.text('Pickup'), findsOneWidget);
      expect(find.text('1. Banke Bihari'), findsOneWidget);
      expect(find.text('Visited'), findsOneWidget);
      expect(find.text('Arrived'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('usage shows time left and distance against the package', (tester) async {
      final circuit = Ride.fromJson(_ride()).circuit!;
      await tester.pumpWidget(host(CircuitUsagePanel(circuit: circuit, running: false)));
      expect(find.text('2h 46m'), findsOneWidget); // 5 h − 2 h 14 m
      expect(find.text('17.4 km'), findsOneWidget);
      expect(find.text('of 30 km included'), findsOneWidget);
    });

    testWidgets('the final bill itemises package and extras', (tester) async {
      final ride = Ride.fromJson(
        _ride(
          status: 'COMPLETED',
          stops: const ['COMPLETED', 'COMPLETED', 'COMPLETED'],
          current: 4,
          finalFare: 725,
          finalBill: {
            'distanceMeters': 35000,
            'durationSeconds': 21600,
            'distanceSource': 'ACTUAL',
            'durationSource': 'ACTUAL',
            'baseFare': 600,
            'distanceCharge': 75,
            'timeCharge': 50,
            'subtotal': 725,
            'minimumFareApplied': false,
            'capApplied': false,
            'total': 725,
            'payable': 725,
          },
        )..update('circuit', (circuit) => (circuit as Map<String, dynamic>)..['settlement'] = {'extraKm': 5, 'extraBlocks': 4, 'usedDistanceMeters': 35000, 'usedDurationSeconds': 21600, 'distanceSource': 'ACTUAL', 'completedBy': 'DRIVER'}),
      );
      await tester.pumpWidget(host(CircuitBillCard(ride: ride)));
      expect(find.text('Final fare'), findsOneWidget);
      expect(find.textContaining('5 km ×'), findsOneWidget);
      expect(find.text('₹75'), findsOneWidget);
      expect(find.text('₹50'), findsOneWidget);
      expect(find.text('₹725'), findsOneWidget);
    });

    testWidgets('driver panel at a stop: continue to the next stop sends the command', (tester) async {
      final repo = _FakeCircuitRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [circuitRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(home: Scaffold(body: DriverCircuitPanel(ride: Ride.fromJson(_ride())))),
        ),
      );
      expect(find.text('CIRCUIT IN PROGRESS'), findsOneWidget);
      expect(find.text('At Nidhivan'), findsOneWidget);
      await tester.tap(find.text('Continue to Keshi Ghat'));
      await tester.pump();
      expect(repo.calls, ['complete:2']);
    });

    testWidgets('driver panel while support resolves a blocked stop offers no commands', (tester) async {
      final repo = _FakeCircuitRepository();
      final ride = Ride.fromJson(
        _ride(
          stops: const ['COMPLETED', 'ARRIVING', 'UPCOMING'],
          exception: {'type': 'STOP_BLOCKED', 'stopOrder': 2, 'reportedAt': '2026-10-05T06:40:00Z'},
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [circuitRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(home: Scaffold(body: DriverCircuitPanel(ride: ride))),
        ),
      );
      expect(find.text('Waiting for Tirvona support'), findsOneWidget);
      expect(find.textContaining('Arrived at'), findsNothing);
      expect(find.textContaining('Continue to'), findsNothing);
    });

    testWidgets('driver panel after the last stop offers only "Complete circuit"', (tester) async {
      final repo = _FakeCircuitRepository();
      final ride = Ride.fromJson(_ride(stops: const ['COMPLETED', 'SKIPPED', 'COMPLETED'], current: 4));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [circuitRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(home: Scaffold(body: DriverCircuitPanel(ride: ride))),
        ),
      );
      expect(find.text('All stops done'), findsOneWidget);
      await tester.tap(find.text('Complete circuit'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Complete'));
      await tester.pump();
      expect(repo.calls, ['completeCircuit']);
    });
  });
}
