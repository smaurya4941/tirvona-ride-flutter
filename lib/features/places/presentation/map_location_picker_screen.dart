import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/maps/tirvona_map.dart';
import '../../../core/theme/app_colors.dart';
import '../../rides/application/booking_controller.dart';
import '../../rides/domain/ride_models.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';
import '../application/current_location.dart';
import '../application/popular_places.dart';
import '../data/places_repository.dart';
import '../domain/place_suggestion.dart';
import 'location_feedback.dart';

const _pinZoom = 17.0;

/// Looks up the address only once the map has settled (Google reports
/// "idle" after flings too, so this only absorbs quick successive drags).
const _settleDelay = Duration(milliseconds: 300);

/// Drop-a-pin picker: the rider moves the map under a fixed centre pin, the
/// address under it is looked up when the map settles, and "Confirm" returns
/// the exact pinned [Place] (via `context.pop`).
class MapLocationPickerScreen extends ConsumerStatefulWidget {
  const MapLocationPickerScreen({super.key, required this.field});

  final PlaceField field;

  @override
  ConsumerState<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState
    extends ConsumerState<MapLocationPickerScreen> {
  GoogleMapController? _map;
  late final LatLng _initialCenter;
  late LatLng _center;
  late final bool _startedWithoutPlace;
  Timer? _settle;
  int _lookup = 0;

  bool _moving = false;
  bool _resolving = true; // until the first lookup answers
  bool _locating = false;
  ReverseGeocodedPlace? _named;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final booking = ref.read(bookingControllerProvider);
    final own = widget.field == PlaceField.pickup
        ? booking.pickup
        : booking.destination;
    final other = widget.field == PlaceField.pickup
        ? booking.destination
        : booking.pickup;
    final device = ref.read(deviceLocationProvider).lastPoint;
    final start =
        own ??
        other ??
        (device == null
            ? null
            : Place(
                address: '',
                latitude: device.latitude,
                longitude: device.longitude,
              ));
    _initialCenter = start == null
        ? TirvonaMap.serviceAreaCenter
        : LatLng(start.latitude, start.longitude);
    _center = _initialCenter;
    _startedWithoutPlace = start == null;
  }

  /// The controller can move the map only once it is ready.
  void _onMapCreated(GoogleMapController controller) {
    _map = controller;
    unawaited(_describe(_center));
    // Nothing to start from: try the device position without prompting.
    if (_startedWithoutPlace) unawaited(_goToMyLocation(prompt: false));
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  void _onCameraMoveStarted() {
    _settle?.cancel();
    if (!_moving) setState(() => _moving = true);
  }

  void _onCameraMove(CameraPosition position) => _center = position.target;

  void _onCameraIdle() {
    // Idle also fires once when the map first loads; _onMapCreated has
    // already started that lookup.
    if (!_moving) return;
    _settle?.cancel();
    _settle = Timer(_settleDelay, () {
      if (!mounted) return;
      setState(() => _moving = false);
      unawaited(_describe(_center));
    });
  }

  Future<void> _describe(LatLng point) async {
    final lookup = ++_lookup;
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final named = await ref.read(placesRepositoryProvider).reverse((
        latitude: point.latitude,
        longitude: point.longitude,
      ));
      if (!mounted || lookup != _lookup) return;
      setState(() {
        _named = named;
        _resolving = false;
      });
    } on Object catch (error) {
      if (!mounted || lookup != _lookup) return;
      setState(() {
        _named = null;
        _error = error;
        _resolving = false;
      });
    }
  }

  Future<void> _goToMyLocation({bool prompt = true}) async {
    setState(() => _locating = true);
    try {
      final point = await ref
          .read(deviceLocationProvider)
          .currentPosition(prompt: prompt);
      if (!mounted) return;
      await _map?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(point.latitude, point.longitude),
          _pinZoom,
        ),
      );
    } on Object catch (error) {
      if (mounted && prompt) showLocationError(context, ref, error);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    final named = _named;
    final point = _center;
    final place = named == null
        // The address lookup failed, but the pin itself is exact.
        ? Place(
            name: 'Pinned location',
            address:
                'Pinned location (${point.latitude.toStringAsFixed(5)}, '
                '${point.longitude.toStringAsFixed(5)})',
            latitude: point.latitude,
            longitude: point.longitude,
          )
        : Place(
            name: named.approximate ? 'Pinned location' : named.place.name,
            address: named.place.address,
            latitude: point.latitude,
            longitude: point.longitude,
          );
    context.pop(place);
  }

  @override
  Widget build(BuildContext context) {
    final isPickup = widget.field == PlaceField.pickup;
    final canConfirm = !_moving && !_resolving;

    return Scaffold(
      appBar: AppBar(
        title: Text(isPickup ? 'Set pickup on map' : 'Set destination on map'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                TirvonaMap(
                  initialCamera: CameraPosition(
                    target: _initialCenter,
                    zoom: _pinZoom,
                  ),
                  minZoom: 5,
                  maxZoom: 20,
                  onMapCreated: _onMapCreated,
                  onCameraMoveStarted: _onCameraMoveStarted,
                  onCameraMove: _onCameraMove,
                  onCameraIdle: _onCameraIdle,
                ),
                // The pin's tip marks the map centre; it lifts while moving.
                IgnorePointer(
                  child: Center(
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 150),
                      offset: Offset(0, _moving ? -0.7 : -0.5),
                      child: Icon(
                        Icons.location_on,
                        size: 48,
                        color: isPickup ? AppColors.success : AppColors.bhagwa,
                        shadows: const [
                          Shadow(blurRadius: 6, color: Colors.black26),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'map-picker-locate',
                    tooltip: 'Go to my location',
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.midnightBlue,
                    onPressed: _locating ? null : _goToMyLocation,
                    child: _locating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PinnedAddress(
                    named: _named,
                    error: _error,
                    busy: _moving || _resolving,
                    onRetry: () => unawaited(_describe(_center)),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: canConfirm ? _confirm : null,
                    child: Text(
                      isPickup ? 'Confirm pickup' : 'Confirm destination',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedAddress extends StatelessWidget {
  const _PinnedAddress({
    required this.named,
    required this.error,
    required this.busy,
    required this.onRetry,
  });

  final ReverseGeocodedPlace? named;
  final Object? error;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String? subtitle;
    if (busy) {
      title = 'Finding address…';
      subtitle = null;
    } else if (error != null) {
      title = 'Pinned location';
      subtitle =
          "Couldn't load the address (${errorMessage(error!)}). "
          'You can still confirm this spot.';
    } else if (named case final named?) {
      title = named.approximate ? 'Pinned location' : named.place.title;
      subtitle = named.approximate
          ? 'No street name here — the driver will use the exact pin.'
          : named.place.address;
    } else {
      title = 'Move the map to place the pin';
      subtitle = null;
    }

    return Row(
      children: [
        const Icon(Icons.place_outlined, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.midnightBlue,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (!busy && error != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
