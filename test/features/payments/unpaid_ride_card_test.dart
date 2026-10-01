import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/core/theme/app_theme.dart';
import 'package:tirvona_ride/features/customer/payments/widgets/payment_widgets.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

import '../rides/ride_models_test.dart' show rideJson;

void main() {
  final unpaid = Ride.fromJson(
    rideJson(
      status: 'COMPLETED',
      extra: {
        'rideCode': 'TRB23E8C4Q',
        'paymentStatus': 'PENDING',
        'fare': {
          'currency': 'INR',
          'baseFare': 30,
          'subtotal': 36,
          'minimumFare': 40,
          'estimatedFare': 36,
          'finalFare': 36,
        },
      },
    ),
  );

  testWidgets(
    'Home "Payment pending" card lays out on a phone with the app theme',
    (tester) async {
      // A typical 1080×2400 Android phone.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            // The real theme: its full-width filled buttons caused the bug.
            theme: AppTheme.light(),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: [UnpaidRideCard(ride: unpaid)],
              ),
            ),
          ),
        ),
      );

      final title = find.text('Payment pending');
      expect(title, findsOneWidget);
      // Regression: the title was squeezed to one letter per line (a few
      // pixels wide). Height is font-dependent in tests, so check width.
      expect(tester.getSize(title).width, greaterThan(150));

      expect(find.text('₹36'), findsOneWidget);
      expect(find.textContaining('Ride TRB23E8C4Q to'), findsOneWidget);
      expect(find.text('Pay now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
