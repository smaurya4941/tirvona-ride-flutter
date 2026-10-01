import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../rides/domain/ride_models.dart';
import '../data/places_repository.dart';
import '../domain/place_suggestion.dart';
import 'current_location.dart';

/// Shorter queries show recent/popular places instead of searching.
const minSearchLength = 2;
const searchDebounce = Duration(milliseconds: 300);

@immutable
class PlaceSearchState {
  const PlaceSearchState({
    this.query = '',
    this.suggestions,
    this.loading = false,
    this.error,
    this.degraded = false,
  });

  final String query;

  /// Results for [query]; null while the query is too short to search (the
  /// screen shows recent and popular places) or before the first answer.
  final List<PlaceSuggestion>? suggestions;

  /// A search for [query] is pending (debounce or request in flight).
  final bool loading;
  final Object? error;

  /// Only popular places could be searched (provider unavailable).
  final bool degraded;

  bool get isSearching => query.length >= minSearchLength;
}

/// Debounced, cancellable autocomplete for the location search screen.
///
/// Every keystroke restarts a short debounce; a newer query cancels the
/// request of an older one, and a late answer for an old query is dropped,
/// so results always match what is in the box. Keystrokes and the final tap
/// share one session token (one billable session with Google Places).
class PlaceSearchController extends Notifier<PlaceSearchState> {
  Timer? _debounce;
  CancelToken? _inFlight;
  String _sessionToken = newSessionToken();

  PlacesRepository get _repository => ref.read(placesRepositoryProvider);

  @override
  PlaceSearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _inFlight?.cancel();
    });
    // Warm a rough position so the first results rank near the rider.
    unawaited(ref.read(deviceLocationProvider).approximatePosition());
    return const PlaceSearchState();
  }

  void search(String text) {
    final query = text.trim();
    if (query == state.query && (state.loading || state.suggestions != null)) {
      return;
    }
    _debounce?.cancel();
    _inFlight?.cancel();
    if (query.length < minSearchLength) {
      state = PlaceSearchState(query: query);
      return;
    }
    // Keep the previous rows visible while the next ones load.
    state = PlaceSearchState(
      query: query,
      suggestions: state.suggestions,
      degraded: state.degraded,
      loading: true,
    );
    _debounce = Timer(searchDebounce, () => unawaited(_run(query)));
  }

  Future<void> retry() => _run(state.query);

  Future<void> _run(String query) async {
    if (query.length < minSearchLength) return;
    final token = CancelToken();
    _inFlight = token;
    try {
      final result = await _repository.autocomplete(
        query,
        near: ref.read(deviceLocationProvider).lastPoint,
        sessionToken: _sessionToken,
        cancelToken: token,
      );
      if (!ref.mounted || token.isCancelled || state.query != query) return;
      state = PlaceSearchState(
        query: query,
        suggestions: result.suggestions,
        degraded: result.degraded,
      );
    } on ApiException catch (error) {
      if (!ref.mounted || error.kind == ApiErrorKind.cancelled) return;
      if (state.query != query) return;
      state = PlaceSearchState(query: query, error: error);
    }
  }

  /// Coordinates for a tapped suggestion (a request only when the provider
  /// sent none). Ends the search session.
  Future<Place> choose(PlaceSuggestion suggestion) async {
    try {
      if (suggestion.hasCoordinates) return suggestion.toPlace();
      return await _repository.resolve(suggestion, sessionToken: _sessionToken);
    } finally {
      _sessionToken = newSessionToken();
    }
  }

  /// Clears the query, e.g. when the other field takes focus.
  void clear() => search('');
}

final placeSearchControllerProvider =
    NotifierProvider.autoDispose<PlaceSearchController, PlaceSearchState>(
      PlaceSearchController.new,
    );

final _random = Random.secure();

/// 16 random bytes, URL-safe (the API accepts 8–64 of `[A-Za-z0-9_-]`).
String newSessionToken() => base64Url
    .encode(List<int>.generate(16, (_) => _random.nextInt(256)))
    .replaceAll('=', '');
