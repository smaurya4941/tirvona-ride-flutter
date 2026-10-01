import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';

import '../../places/application/current_location.dart';
import '../../places/application/recent_places.dart';
import '../data/ride_repository.dart';
import '../domain/promo_models.dart';
import '../domain/ride_models.dart';

class BookingState {
  const BookingState({
    this.pickup,
    this.destination,
    this.estimates = const AsyncData([]),
    this.selectedType,
    this.locatingPickup = false,
    this.pickupLocationError,
    this.promo,
    this.savedPromo,
    this.savedPromoProblem,
  });

  /// Null until the rider's location is found or they choose a pickup.
  final Place? pickup;
  final Place? destination;

  /// Server quotes for every bookable ride type on the current trip.
  final AsyncValue<List<FareEstimate>> estimates;
  final RideTypeCode? selectedType;

  /// "Use current location" is running for the pickup.
  final bool locatingPickup;

  /// Why the last automatic/current-location pickup attempt failed
  /// ([LocationFailure] or an API error); cleared once a pickup is set.
  final Object? pickupLocationError;

  /// A promo the server accepted for the current trip and ride type. Cleared
  /// whenever either changes; the server validates it again at booking.
  final PromoQuote? promo;

  /// A code the rider picked before choosing a trip (Offers tab). It is
  /// applied automatically on "Choose a ride" and kept until the rider
  /// removes it or books with it.
  final PromoOffer? savedPromo;

  /// Why [savedPromo] does not apply to the current trip and ride type
  /// (ride type not covered, fare too low…), as the server explained it.
  final String? savedPromoProblem;

  bool get hasTrip =>
      pickup != null && destination != null && !pickup!.sameSpot(destination!);

  FareEstimate? get selectedEstimate {
    final list = estimates.value;
    if (list == null || selectedType == null) return null;
    for (final estimate in list) {
      if (estimate.rideType == selectedType) return estimate;
    }
    return null;
  }

  BookingState copyWith({
    Place? pickup,
    Place? destination,
    bool clearDestination = false,
    AsyncValue<List<FareEstimate>>? estimates,
    RideTypeCode? selectedType,
    bool clearSelection = false,
    bool? locatingPickup,
    Object? pickupLocationError,
    bool clearPickupLocationError = false,
    PromoQuote? promo,
    bool clearPromo = false,
    PromoOffer? savedPromo,
    bool clearSavedPromo = false,
    String? savedPromoProblem,
    bool clearSavedPromoProblem = false,
  }) => BookingState(
    pickup: pickup ?? this.pickup,
    destination: clearDestination ? null : destination ?? this.destination,
    estimates: estimates ?? this.estimates,
    selectedType: clearSelection ? null : selectedType ?? this.selectedType,
    locatingPickup: locatingPickup ?? this.locatingPickup,
    pickupLocationError: clearPickupLocationError
        ? null
        : pickupLocationError ?? this.pickupLocationError,
    promo: clearPromo ? null : promo ?? this.promo,
    savedPromo: clearSavedPromo ? null : savedPromo ?? this.savedPromo,
    savedPromoProblem: clearSavedPromo || clearSavedPromoProblem
        ? null
        : savedPromoProblem ?? this.savedPromoProblem,
  );
}

/// Holds the trip being booked across Home → Where to? → Choose a ride
/// (quotes, promo, confirm). Quotes shown here are advisory; [book] lets the
/// server re-price.
class BookingController extends Notifier<BookingState> {
  /// Guards against a slow response for an old trip overwriting a newer one.
  int _quoteGeneration = 0;

  /// Guards against a slow location fix overwriting a pickup chosen since.
  int _locateGeneration = 0;
  bool _autoLocateTried = false;

  @override
  BookingState build() => const BookingState();

  /// [remember] adds the place to the rider's recent places (not wanted
  /// for "current location", which changes with every trip).
  void setPickup(Place place, {bool remember = true}) {
    _locateGeneration++;
    _changeTrip(
      state.copyWith(
        pickup: place,
        locatingPickup: false,
        clearPickupLocationError: true,
      ),
    );
    if (remember) _remember(place);
  }

  void setDestination(Place place, {bool remember = true}) {
    _changeTrip(state.copyWith(destination: place));
    if (remember) _remember(place);
  }

  void clearDestination() =>
      _changeTrip(state.copyWith(clearDestination: true));

  void swap() {
    final pickup = state.pickup;
    final destination = state.destination;
    if (pickup == null || destination == null) return;
    _locateGeneration++;
    _changeTrip(
      BookingState(
        pickup: destination,
        destination: pickup,
        selectedType: state.selectedType,
        savedPromo: state.savedPromo,
      ),
    );
  }

  /// Sets the pickup to where the rider is now. Returns the failure (a
  /// [LocationFailure] or API error) for the caller to explain, or null.
  Future<Object?> useCurrentLocationForPickup({bool prompt = true}) async {
    final generation = ++_locateGeneration;
    state = state.copyWith(
      locatingPickup: true,
      clearPickupLocationError: true,
    );
    try {
      final place = await ref
          .read(currentPlaceLocatorProvider)
          .locate(prompt: prompt);
      if (!ref.mounted || generation != _locateGeneration) return null;
      _changeTrip(state.copyWith(pickup: place, locatingPickup: false));
      return null;
    } on Object catch (error) {
      if (!ref.mounted || generation != _locateGeneration) return null;
      state = state.copyWith(locatingPickup: false, pickupLocationError: error);
      return error;
    }
  }

  /// Like opening Uber: the first time Home shows without a pickup, fill it
  /// from the device location (asking for permission once).
  Future<void> ensurePickup() async {
    if (_autoLocateTried || state.pickup != null || state.locatingPickup) {
      return;
    }
    _autoLocateTried = true;
    await useCurrentLocationForPickup();
  }

  /// A promo is priced for one ride type, so changing type drops it (a
  /// saved code is then tried again for the new type).
  void select(RideTypeCode type) {
    state = state.copyWith(
      selectedType: type,
      clearPromo: state.promo != null && state.promo!.rideType != type,
      clearSavedPromoProblem: true,
    );
    unawaited(_applySavedPromo());
  }

  /// Asks the server whether [code] applies to the selected trip. Throws the
  /// server's ApiException (PROMO_INVALID, PROMO_EXPIRED, …) when it does not.
  Future<PromoQuote> applyPromo(String code) async {
    final pickup = state.pickup;
    final destination = state.destination;
    final type = state.selectedType;
    if (!state.hasTrip ||
        pickup == null ||
        destination == null ||
        type == null) {
      throw StateError('Choose a trip and ride type first');
    }
    final quote = await ref
        .read(rideRepositoryProvider)
        .validatePromo(
          code: code.trim().toUpperCase(),
          rideType: type,
          pickup: pickup,
          destination: destination,
        );
    // Only if the rider is still on the trip and ride type it was priced for.
    if (ref.mounted &&
        state.selectedType == type &&
        identical(state.pickup, pickup) &&
        identical(state.destination, destination)) {
      state = state.copyWith(promo: quote, clearSavedPromoProblem: true);
    }
    return quote;
  }

  /// Saves [code] before a trip is chosen (Offers tab). The server checks
  /// the code itself now; ride type and fare are checked once the rider
  /// picks a ride, where it is applied automatically. Throws the server's
  /// ApiException (PROMO_INVALID, PROMO_EXPIRED, …) when it cannot be used.
  Future<PromoOffer> savePromo(String code) async {
    final offer = await ref
        .read(rideRepositoryProvider)
        .checkPromo(code.trim().toUpperCase());
    if (!ref.mounted) return offer;
    state = state.copyWith(
      savedPromo: offer,
      clearSavedPromoProblem: true,
      clearPromo: state.promo != null && state.promo!.code != offer.code,
    );
    await _applySavedPromo();
    return offer;
  }

  /// Drops the applied promo and any saved code.
  void removePromo() =>
      state = state.copyWith(clearPromo: true, clearSavedPromo: true);

  /// Applies the saved code to the current trip and ride type, if any. A
  /// code that no longer works at all is forgotten; one that just does not
  /// fit this ride (type, minimum fare) is kept for another ride type or trip.
  Future<void> _applySavedPromo() async {
    final saved = state.savedPromo;
    if (saved == null ||
        state.promo != null ||
        !state.hasTrip ||
        state.selectedType == null) {
      return;
    }
    try {
      await applyPromo(saved.code);
    } on ApiException catch (error) {
      if (!ref.mounted || state.savedPromo?.code != saved.code) return;
      if (!(error.code?.startsWith('PROMO_') ?? false)) return;
      state = _promoFitsOtherRides.contains(error.code)
          ? state.copyWith(savedPromoProblem: error.message)
          : state.copyWith(
              clearSavedPromo: true,
              savedPromoProblem: error.message,
            );
    } catch (_) {
      // Network trouble: say so; tapping the row lets the rider retry.
      if (!ref.mounted || state.savedPromo?.code != saved.code) return;
      state = state.copyWith(
        savedPromoProblem: 'Could not apply it right now. Tap to try again.',
      );
    }
  }

  Future<void> loadEstimates() async {
    final pickup = state.pickup;
    final destination = state.destination;
    if (!state.hasTrip || pickup == null || destination == null) return;
    final generation = ++_quoteGeneration;
    state = state.copyWith(estimates: const AsyncLoading());
    final result = await AsyncValue.guard(
      () => ref
          .read(rideRepositoryProvider)
          .estimateAll(pickup: pickup, destination: destination),
    );
    if (generation != _quoteGeneration) return;

    final quotes = result.value;
    final keepSelection =
        quotes != null &&
        quotes.any((quote) => quote.rideType == state.selectedType);
    state = state.copyWith(
      estimates: result,
      selectedType: keepSelection
          ? state.selectedType
          : (quotes != null && quotes.isNotEmpty
                ? quotes.first.rideType
                : null),
      clearSelection: !keepSelection && (quotes == null || quotes.isEmpty),
    );
    await _applySavedPromo();
  }

  /// Creates the ride; the backend recalculates distance, duration and fare.
  Future<Ride> book() {
    final pickup = state.pickup;
    final destination = state.destination;
    final type = state.selectedType;
    if (!state.hasTrip ||
        pickup == null ||
        destination == null ||
        type == null) {
      throw StateError('Choose a pickup, destination and ride type first');
    }
    return ref
        .read(rideRepositoryProvider)
        .book(
          rideType: type,
          pickup: pickup,
          destination: destination,
          promoCode: state.promo?.code,
        );
  }

  /// After a booking: keep the pickup, clear the rest.
  void reset() {
    _quoteGeneration++;
    state = BookingState(pickup: state.pickup);
  }

  void _changeTrip(BookingState next) {
    _quoteGeneration++;
    // A new trip means a new fare: any applied promo must be re-checked.
    state = next.copyWith(
      estimates: const AsyncData([]),
      clearPromo: true,
      clearSavedPromoProblem: true,
    );
  }

  void _remember(Place place) {
    // Recents are a convenience: never let storage trouble block booking.
    ref.read(recentPlacesProvider.notifier).remember(place).ignore();
  }
}

/// Refusals that only mean "not for this ride": the code stays saved.
const _promoFitsOtherRides = {
  'PROMO_RIDE_TYPE_NOT_ELIGIBLE',
  'PROMO_MIN_FARE_NOT_MET',
};

final bookingControllerProvider =
    NotifierProvider<BookingController, BookingState>(BookingController.new);
