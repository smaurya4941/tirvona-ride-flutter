import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../../auth/presentation/session_controller.dart';
import '../../rides/domain/ride_models.dart';
import '../data/places_repository.dart';
import '../domain/saved_place.dart';

/// The rider's saved Home, Work and own places, stored on the server (`/places/saved`)
/// so they follow the account to a new phone.
class SavedPlacesController extends AsyncNotifier<SavedPlaces> {
  PlacesRepository get _repository => ref.read(placesRepositoryProvider);

  @override
  Future<SavedPlaces> build() async {
    // Re-read when the signed-in user changes.
    final userId = ref.watch(
      sessionControllerProvider.select((session) => session.user?.id),
    );
    if (userId == null) return const SavedPlaces();
    final saved = await _repository.savedPlaces();
    return _migrateDeviceCopy(userId, saved);
  }

  Future<void> save(SavedPlaceKind kind, Place place) async {
    state = AsyncData(await _repository.savePlace(kind, place));
  }

  Future<void> clear(SavedPlaceKind kind) async {
    state = AsyncData(await _repository.clearSavedPlace(kind));
  }

  Future<void> addOther(String label, Place place) async {
    state = AsyncData(await _repository.addOtherPlace(label, place));
  }

  Future<void> updateOther(String id, {String? label, Place? place}) async {
    state = AsyncData(
      await _repository.updateOtherPlace(id, label: label, place: place),
    );
  }

  Future<void> removeOther(String id) async {
    state = AsyncData(await _repository.removeOtherPlace(id));
  }

  /// Builds before this release kept Home/Work on the device only. Upload
  /// what the server does not have yet, once, then drop the device copy.
  Future<SavedPlaces> _migrateDeviceCopy(
    String userId,
    SavedPlaces server,
  ) async {
    final storage = ref.read(secureStorageProvider);
    final key = 'places.saved.$userId';
    try {
      final raw = await storage.read(key);
      if (raw == null) return server;
      var merged = server;
      final local = jsonDecode(raw);
      if (local is Map<String, dynamic>) {
        for (final kind in SavedPlaceKind.values) {
          final place = _decode(local[kind.name]);
          if (place != null && merged[kind] == null) {
            merged = await _repository.savePlace(kind, place);
          }
        }
      }
      await storage.delete(key);
      return merged;
    } on Object {
      // Try again next launch; the server copy is still correct.
      return server;
    }
  }

  static Place? _decode(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final address = json['address'];
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    if (address is! String || latitude is! num || longitude is! num) {
      return null;
    }
    return Place(
      name: json['name'] as String?,
      address: address,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  }
}

final savedPlacesProvider =
    AsyncNotifierProvider<SavedPlacesController, SavedPlaces>(
      SavedPlacesController.new,
    );
