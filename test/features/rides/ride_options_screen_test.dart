import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/core/network/api_exception.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';
import 'package:tirvona_ride/features/rides/application/booking_controller.dart';
import 'package:tirvona_ride/features/rides/data/ride_repository.dart';
import 'package:tirvona_ride/features/rides/domain/promo_models.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';
import 'package:tirvona_ride/features/rides/presentation/customer/ride_options_screen.dart';

import '../places/places_fakes.dart';
import 'ride_models_test.dart' show rideJson;

const _fare = FareBreakdown(
  currency: 'INR',
  baseFare: 20,
  perKmRate: 5,
  perMinuteRate: 1,
  minimumFare: 30,
  distanceCharge: 42,
  timeCharge: 18,
  subtotal: 80,
  minimumFareApplied: false,
  estimatedFare: 65,
);

FareEstimate _quote(
  RideTypeCode type,
  String name,
  double price, {
  int? etaSeconds,
  int nearby = 0,
}) => FareEstimate(
  rideType: type,
  displayName: name,
  icon: type.wireName.toLowerCase(),
  seatCapacity: type == RideTypeCode.bike ? 1 : 3,
  distanceMeters: 8400,
  durationSeconds: 18 * 60,
  fare: FareBreakdown(
    currency: 'INR',
    baseFare: _fare.baseFare,
    perKmRate: _fare.perKmRate,
    perMinuteRate: _fare.perMinuteRate,
    minimumFare: _fare.minimumFare,
    distanceCharge: _fare.distanceCharge,
    timeCharge: _fare.timeCharge,
    subtotal: _fare.subtotal,
    minimumFareApplied: false,
    estimatedFare: price,
  ),
  pickupEtaSeconds: etaSeconds,
  driversNearby: nearby,
);

/// Quotes and bookings controlled by the test.
class _Rides extends RideRepository {
  _Rides() : super(Dio());

  List<FareEstimate> quotes = [
    _quote(RideTypeCode.bike, 'Bike', 65, etaSeconds: 180, nearby: 2),
    _quote(RideTypeCode.auto, 'Auto (Rickshaw)', 95, etaSeconds: 120, nearby: 1),
    _quote(RideTypeCode.cab, 'Cab', 160),
  ];
  final quotedTrips = <(Place, Place)>[];
  final bookings = <({RideTypeCode type, String? promo})>[];
  Object? bookingError;
  final promoChecks = <(String, RideTypeCode)>[];

  @override
  Future<PromoQuote> validatePromo({
    required String code,
    required RideTypeCode rideType,
    required Place pickup,
    required Place destination,
  }) async {
    promoChecks.add((code, rideType));
    return PromoQuote(
      code: code,
      title: '₹20 off',
      rideType: rideType,
      fare: 65,
      discount: 20,
      payableFare: 45,
    );
  }

  @override
  Future<List<FareEstimate>> estimateAll({
    required Place pickup,
    required Place destination,
  }) async {
    quotedTrips.add((pickup, destination));
    return quotes;
  }

  @override
  Future<Ride> book({
    required RideTypeCode rideType,
    required Place pickup,
    required Place destination,
    String? promoCode,
  }) async {
    bookings.add((type: rideType, promo: promoCode));
    final error = bookingError;
    if (error != null) throw error;
    return Ride.fromJson(rideJson(status: 'SEARCHING'));
  }
}

void main() {
  late _Rides rides;
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    rides = _Rides();
    container = ProviderContainer(
      overrides: [
        rideRepositoryProvider.overrideWithValue(rides),
        sessionControllerProvider.overrideWith(FakeSession.new),
      ],
    );
    addTearDown(container.dispose);
  });

  BookingState booking() => container.read(bookingControllerProvider);

  Future<void> pumpOptions(WidgetTester tester) async {
    // Placeholder instead of the native Google map in widget tests.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);

    container.read(bookingControllerProvider.notifier)
      ..setPickup(premMandir, remember: false)
      ..setDestination(bankeBihari, remember: false);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(AppRoutes.customerRideOptions),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.customerRideOptions,
          builder: (context, state) => const RideOptionsScreen(),
        ),
        GoRoute(
          path: AppRoutes.customerPlaceSearch,
          builder: (context, state) => Scaffold(
            body: Text('SEARCH ${state.uri.queryParameters['field']}'),
          ),
        ),
        GoRoute(
          path: AppRoutes.customerRidePattern,
          builder: (context, state) =>
              Scaffold(body: Text('RIDE ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  void done() => debugDefaultTargetPlatformOverride = null;

  testWidgets(
    'quotes every ride type with fare, driver ETA and trip time, and books '
    'the chosen one',
    (tester) async {
      await pumpOptions(tester);

      // Opened without quotes: it fetches them for this trip.
      expect(rides.quotedTrips, [(premMandir, bankeBihari)]);
      expect(find.text('Prem Mandir'), findsOneWidget);
      expect(find.text('Banke Bihari Temple'), findsOneWidget);
      expect(find.text('8.4 km • 18 min'), findsOneWidget);
      expect(find.text('Choose a ride'), findsOneWidget);
      expect(find.text('Bike'), findsOneWidget);
      expect(find.text('3 min away'), findsOneWidget);
      expect(find.text('2 min away'), findsOneWidget);
      expect(find.text('No drivers nearby right now'), findsOneWidget);
      expect(find.text('~ 18 min • 8.4 km'), findsNWidgets(3));
      expect(find.text('Best Price'), findsOneWidget);

      // The first quote is pre-selected; choosing another switches it.
      expect(find.text('Confirm Bike'), findsOneWidget);
      await tester.tap(find.text('Auto (Rickshaw)'));
      await tester.pumpAndSettle();
      expect(booking().selectedType, RideTypeCode.auto);
      expect(find.text('Confirm Auto (Rickshaw)'), findsOneWidget);

      await tester.tap(find.text('Confirm Auto (Rickshaw)'));
      await tester.pumpAndSettle();
      expect(rides.bookings.single.type, RideTypeCode.auto);
      expect(find.text('RIDE 66f0c0ffee0000000000abcd'), findsOneWidget);
      // The trip is done with; the pickup stays for the next one.
      expect(booking().destination, isNull);
      expect(booking().pickup, premMandir);
      done();
    },
  );

  testWidgets('an already active ride opens that ride instead', (
    tester,
  ) async {
    rides.bookingError = const ApiException(
      kind: ApiErrorKind.client,
      message: 'You already have a ride in progress.',
      code: 'RIDE_ALREADY_ACTIVE',
      data: {'rideId': 'existing-ride'},
    );
    await pumpOptions(tester);
    await tester.tap(find.text('Confirm Bike'));
    await tester.pumpAndSettle();
    expect(find.text('RIDE existing-ride'), findsOneWidget);
    done();
  });

  testWidgets('a promo that stopped applying is dropped and explained', (
    tester,
  ) async {
    await pumpOptions(tester);
    // The server accepts the code for the selected ride (as the promo sheet
    // does it).
    await container
        .read(bookingControllerProvider.notifier)
        .applyPromo('save20');
    await tester.pumpAndSettle();
    expect(rides.promoChecks, [('SAVE20', RideTypeCode.bike)]);
    expect(find.text('₹45'), findsOneWidget);
    expect(find.textContaining('SAVE20 applied'), findsOneWidget);

    rides.bookingError = const ApiException(
      kind: ApiErrorKind.client,
      message: 'This promo code has expired.',
      code: 'PROMO_EXPIRED',
    );
    await tester.tap(find.text('Confirm Bike'));
    await tester.pumpAndSettle();
    expect(rides.bookings.single.promo, 'SAVE20');
    expect(find.text('This promo code has expired.'), findsOneWidget);
    expect(booking().promo, isNull);
    await tester.scrollUntilVisible(find.text('Apply a promo code'), 80);
    expect(find.text('Apply a promo code'), findsOneWidget);
    // Back to the normal fare.
    expect(find.text('₹45'), findsNothing);
    done();
  });

  testWidgets('swap re-quotes the reversed trip; Change goes back to search', (
    tester,
  ) async {
    await pumpOptions(tester);
    await tester.tap(find.byTooltip('Swap pickup and destination'));
    await tester.pumpAndSettle();
    expect(booking().pickup, bankeBihari);
    expect(rides.quotedTrips.last, (bankeBihari, premMandir));
    // The ride type chosen before the swap is kept.
    expect(booking().selectedType, RideTypeCode.bike);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('SEARCH destination'), findsOneWidget);
    done();
  });

  testWidgets('shows the fare breakdown for a ride type', (tester) async {
    await pumpOptions(tester);
    await tester.tap(find.byTooltip('Fare details for Cab'));
    await tester.pumpAndSettle();
    expect(find.text('Fare breakdown'), findsOneWidget);
    expect(find.text('Up to 3 passengers'), findsOneWidget);
    done();
  });

  testWidgets('nothing bookable: explains and disables confirm', (
    tester,
  ) async {
    rides.quotes = const [];
    await pumpOptions(tester);
    expect(find.textContaining('No rides are available'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    done();
  });
}
