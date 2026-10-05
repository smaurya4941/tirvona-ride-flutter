import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';
import 'package:tirvona_ride/features/rides/presentation/widgets/ride_widgets.dart';

Map<String, dynamic> _fare({bool peak = false}) => {
  'currency': 'INR',
  'baseFare': 100,
  'perKmRate': peak ? 27 : 18,
  'basePerKmRate': 18,
  if (peak)
    'peak': {
      'name': 'Evening Peak',
      'hikePercent': 50,
      'startTime': '16:00',
      'endTime': '20:00',
      'surcharge': 90,
    },
  'perMinuteRate': 2,
  'minimumFare': 100,
  'distanceCharge': peak ? 270 : 180,
  'timeCharge': 30,
  'subtotal': peak ? 400 : 310,
  'minimumFareApplied': false,
  'estimatedFare': peak ? 400 : 310,
};

void main() {
  group('peak pricing in fares', () {
    test('parses the peak the server applied', () {
      final fare = FareBreakdown.fromJson(_fare(peak: true));
      expect(fare.isPeak, isTrue);
      expect(fare.perKmRate, 27);
      expect(fare.basePerKmRate, 18);
      expect(fare.peak?.name, 'Evening Peak');
      expect(fare.peak?.hikeLabel, '+50%');
      expect(fare.peak?.surcharge, 90);
    });

    test('is absent at normal pricing and on older servers', () {
      final normal = FareBreakdown.fromJson(_fare());
      expect(normal.isPeak, isFalse);
      expect(normal.perKmRate, 18);

      final old = Map<String, dynamic>.from(_fare())..remove('basePerKmRate');
      expect(FareBreakdown.fromJson(old).basePerKmRate, isNull);
    });

    test('formats fractional hikes', () {
      expect(const PeakFare(name: 'x', hikePercent: 12.5).hikeLabel, '+12.5%');
    });

    Future<void> pump(WidgetTester tester, FareBreakdown fare) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FareBreakdownCard(
              fare: fare,
              distanceMeters: 10000,
              durationSeconds: 900,
            ),
          ),
        ),
      ),
    );

    testWidgets('the breakdown explains a peak rate', (tester) async {
      await pump(tester, FareBreakdown.fromJson(_fare(peak: true)));
      expect(find.textContaining('Peak pricing +50%'), findsOneWidget);
      expect(find.textContaining('₹18 → ₹27/km'), findsOneWidget);
      expect(find.textContaining('₹27/km)'), findsWidgets);
      expect(find.text('₹400'), findsWidgets);
    });

    testWidgets('the breakdown has no peak note at normal pricing', (tester) async {
      await pump(tester, FareBreakdown.fromJson(_fare()));
      expect(find.textContaining('Peak pricing'), findsNothing);
    });
  });
}
