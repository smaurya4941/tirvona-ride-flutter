import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/core/network/api_exception.dart';
import 'package:tirvona_ride/core/theme/app_theme.dart';
import 'package:tirvona_ride/features/rides/application/booking_controller.dart';
import 'package:tirvona_ride/features/rides/data/ride_repository.dart';
import 'package:tirvona_ride/features/rides/domain/promo_models.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';
import 'package:tirvona_ride/features/rides/presentation/customer/promo_code_sheet.dart';

import '../places/places_fakes.dart';

PromoOffer _offer(String code, {List<String> rideTypes = const []}) =>
    PromoOffer.fromJson({
      'code': code,
      'title': '₹20 off your ride',
      'discountType': 'FLAT',
      'discountValue': 20,
      'minRideValue': 50,
      'applicableRideTypes': rideTypes,
      'endsAt': '2026-12-31T00:00:00.000Z',
    });

ApiException _promoError(String code, String message) => ApiException(
  kind: ApiErrorKind.client,
  message: message,
  statusCode: 400,
  code: code,
);

/// Server answers controlled by the test: BRAJ20 is AUTO-only.
class _Rides extends RideRepository {
  _Rides() : super(Dio());

  final checked = <String>[];
  final validated = <(String, RideTypeCode)>[];
  List<PromoOffer> offers = [_offer('BRAJ20', rideTypes: ['AUTO'])];

  @override
  Future<List<PromoOffer>> promoOffers() async => offers;

  @override
  Future<PromoOffer> checkPromo(String code) async {
    checked.add(code);
    if (code == 'OLD10') {
      throw _promoError('PROMO_EXPIRED', 'This promo code has expired');
    }
    if (code != 'BRAJ20') {
      throw _promoError('PROMO_INVALID', 'This promo code is not valid');
    }
    return _offer('BRAJ20', rideTypes: ['AUTO']);
  }

  @override
  Future<PromoQuote> validatePromo({
    required String code,
    required RideTypeCode rideType,
    required Place pickup,
    required Place destination,
  }) async {
    validated.add((code, rideType));
    if (rideType != RideTypeCode.auto) {
      throw _promoError(
        'PROMO_RIDE_TYPE_NOT_ELIGIBLE',
        'This promo code cannot be used for this ride type',
      );
    }
    return PromoQuote(
      code: code,
      title: '₹20 off',
      rideType: rideType,
      fare: 95,
      discount: 20,
      payableFare: 75,
    );
  }
}

void main() {
  late _Rides rides;
  late ProviderContainer container;

  setUp(() {
    rides = _Rides();
    container = ProviderContainer(
      overrides: [rideRepositoryProvider.overrideWithValue(rides)],
    );
    addTearDown(container.dispose);
  });

  BookingState booking() => container.read(bookingControllerProvider);
  BookingController controller() =>
      container.read(bookingControllerProvider.notifier);

  void chooseTrip(RideTypeCode type) => controller()
    ..setPickup(premMandir, remember: false)
    ..setDestination(bankeBihari, remember: false)
    ..select(type);

  group('Saved promo (Offers tab)', () {
    test('a code saved before a trip is applied once a fitting ride is chosen',
        () async {
      final offer = await controller().savePromo(' braj20 ');
      expect(rides.checked, ['BRAJ20']);
      expect(offer.code, 'BRAJ20');
      expect(booking().savedPromo?.code, 'BRAJ20');
      expect(booking().promo, isNull);

      // Bike is not covered: the code stays saved with the server's reason.
      chooseTrip(RideTypeCode.bike);
      await pumpEventQueue();
      expect(booking().promo, isNull);
      expect(booking().savedPromo?.code, 'BRAJ20');
      expect(booking().savedPromoProblem, contains('ride type'));

      // Auto is: it is applied without the rider typing it again.
      controller().select(RideTypeCode.auto);
      await pumpEventQueue();
      expect(booking().promo?.discount, 20);
      expect(booking().savedPromoProblem, isNull);
      expect(rides.validated.last, ('BRAJ20', RideTypeCode.auto));
    });

    test('a code that cannot be used at all is refused and not saved',
        () async {
      await expectLater(
        controller().savePromo('OLD10'),
        throwsA(isA<ApiException>()),
      );
      expect(booking().savedPromo, isNull);
    });

    test('removing the promo forgets the saved code', () async {
      chooseTrip(RideTypeCode.auto);
      await controller().savePromo('BRAJ20');
      expect(booking().promo?.code, 'BRAJ20');
      controller().removePromo();
      expect(booking().promo, isNull);
      expect(booking().savedPromo, isNull);
    });
  });

  group('Promo sheet', () {
    Future<List<String?>> open(WidgetTester tester) async {
      final results = <String?>[];
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          // The real theme: its full-width filled buttons once broke the
          // sheet's layout (nothing visible while typing).
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async =>
                        results.add(await showPromoCodeSheet(context)),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('typing shows the code and saves it when there is no trip', (
      tester,
    ) async {
      final results = await open(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Available offers'), findsOneWidget);
      expect(find.text('BRAJ20'), findsOneWidget);
      expect(find.textContaining('For Auto'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'braj-20');
      await tester.pump();
      // Upper-cased, letters and digits only.
      expect(find.widgetWithText(TextField, 'BRAJ20'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(rides.checked, ['BRAJ20']);
      expect(results.single, contains('BRAJ20 saved'));
      expect(booking().savedPromo?.code, 'BRAJ20');
    });

    testWidgets('shows the server reason for a bad code', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'nope99');
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(find.text('This promo code is not valid'), findsOneWidget);
      expect(booking().savedPromo, isNull);
    });

    testWidgets('on "Choose a ride" an offer is priced for the chosen ride', (
      tester,
    ) async {
      chooseTrip(RideTypeCode.auto);
      final results = await open(tester);
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(rides.validated.single, ('BRAJ20', RideTypeCode.auto));
      expect(results.single, 'BRAJ20 applied · you save ₹20');
      expect(booking().promo?.code, 'BRAJ20');
    });
  });
}
