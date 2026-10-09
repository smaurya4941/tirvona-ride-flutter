import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';
import 'package:tirvona_ride/features/rides/presentation/driver/end_ride_widgets.dart';

import 'ride_models_test.dart' show rideJson;

void main() {
  group('end-of-trip OTP models', () {
    test('the rider\'s view carries an END code', () {
      final ride = Ride.fromJson(
        rideJson(
          status: 'RIDE_STARTED',
          extra: {
            'endRequestedAt': '2026-10-07T08:00:00.000Z',
            'otp': {
              'code': '4821',
              'purpose': 'END',
              'expiresAt': '2026-10-07T08:15:00.000Z',
            },
          },
        ),
      );
      expect(ride.otp!.code, '4821');
      expect(ride.otp!.purpose, RideOtpPurpose.end);
      expect(ride.otp!.isEnd, isTrue);
      expect(ride.endRequested, isTrue);
    });

    test('a start code without a purpose stays a start code', () {
      final ride = Ride.fromJson(
        rideJson(
          extra: {
            'otp': {'code': '1234'},
          },
        ),
      );
      expect(ride.otp!.purpose, RideOtpPurpose.start);
      expect(ride.otp!.isEnd, isFalse);
      expect(ride.endRequested, isFalse);
    });

    test('the driver view carries the wait, never a code', () {
      final ride = Ride.fromJson(
        rideJson(
          status: 'RIDE_STARTED',
          extra: {
            'endRequestedAt': '2026-10-07T08:00:00.000Z',
            'endOtp': {
              'requestedAt': '2026-10-07T08:00:00.000Z',
              'expiresAt': '2026-10-07T08:15:00.000Z',
              'overrideAvailableAt': '2026-10-07T08:02:00.000Z',
            },
          },
        ),
      );
      expect(ride.otp, isNull);
      expect(ride.endRequested, isTrue);
      final endOtp = ride.endOtp!;
      expect(
        endOtp.overrideIn(DateTime.utc(2026, 10, 7, 8, 0, 30)),
        const Duration(seconds: 90),
      );
      expect(endOtp.overrideIn(DateTime.utc(2026, 10, 7, 8, 3)), Duration.zero);
    });

    test('a ride that is not in progress is not "ending"', () {
      final ride = Ride.fromJson(
        rideJson(
          status: 'COMPLETED',
          extra: {
            'endRequestedAt': '2026-10-07T08:00:00.000Z',
            'completionMode': 'DRIVER_OVERRIDE',
          },
        ),
      );
      expect(ride.endRequested, isFalse);
      expect(ride.completionMode, 'DRIVER_OVERRIDE');
    });
  });

  group('RiderNotRespondingCard', () {
    final requestedAt = DateTime.utc(2026, 10, 7, 8);
    final endOtp = RideEndOtp(
      requestedAt: requestedAt,
      overrideAvailableAt: requestedAt.add(const Duration(minutes: 2)),
    );

    Future<List<String>> pump(
      WidgetTester tester, {
      required DateTime Function() now,
      bool sosOpen = false,
    }) async {
      final reasons = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RiderNotRespondingCard(
                endOtp: endOtp,
                busy: false,
                sosOpen: sosOpen,
                now: now,
                onEndWithoutCode: (reason) async => reasons.add(reason),
              ),
            ),
          ),
        ),
      );
      return reasons;
    }

    Finder button() => find.byType(OutlinedButton);

    testWidgets('is locked and counts down until the server allows it', (
      tester,
    ) async {
      await pump(
        tester,
        now: () => requestedAt.add(const Duration(seconds: 30)),
      );
      expect(find.text('Available in 1:30'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(button()).onPressed,
        isNull,
        reason: 'the server would refuse it',
      );
    });

    testWidgets('unlocks once the wait is over', (tester) async {
      await pump(
        tester,
        now: () => requestedAt.add(const Duration(minutes: 3)),
      );
      expect(find.text('End without code'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button()).onPressed, isNotNull);
    });

    testWidgets('an open SOS needs no wait', (tester) async {
      await pump(tester, now: () => requestedAt, sosOpen: true);
      expect(find.text('End without code'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button()).onPressed, isNotNull);
    });

    testWidgets('sends the chosen reason, plus the driver\'s note', (
      tester,
    ) async {
      final reasons = await pump(
        tester,
        now: () => requestedAt.add(const Duration(minutes: 3)),
      );
      await tester.tap(button());
      await tester.pumpAndSettle();

      // Nothing chosen yet: cannot confirm.
      FilledButton endTrip() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'End trip'),
      );
      expect(endTrip().onPressed, isNull);

      await tester.tap(find.text('Rider left the vehicle'));
      await tester.pump();
      expect(endTrip().onPressed, isNotNull);
      await tester.enterText(find.byType(TextField), 'Walked into a temple');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'End trip'));
      await tester.pumpAndSettle();
      expect(reasons, ['Rider left the vehicle: Walked into a temple']);
    });

    testWidgets('"Other" needs the driver to say what happened', (
      tester,
    ) async {
      final reasons = await pump(
        tester,
        now: () => requestedAt.add(const Duration(minutes: 3)),
      );
      await tester.tap(button());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Other'));
      await tester.pump();
      FilledButton endTrip() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'End trip'),
      );
      expect(endTrip().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(endTrip().onPressed, isNull, reason: 'the server wants 5+ chars');
      await tester.enterText(
        find.byType(TextField),
        'Rider got into another car',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'End trip'));
      await tester.pumpAndSettle();
      expect(reasons, ['Rider got into another car']);
    });

    testWidgets('"Keep waiting" sends nothing', (tester) async {
      final reasons = await pump(
        tester,
        now: () => requestedAt.add(const Duration(minutes: 3)),
      );
      await tester.tap(button());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep waiting'));
      await tester.pumpAndSettle();
      expect(reasons, isEmpty);
    });
  });
}
