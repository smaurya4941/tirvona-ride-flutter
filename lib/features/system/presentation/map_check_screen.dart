import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/maps/tirvona_map.dart';
import '../../places/application/current_location.dart';

/// Diagnostics: proves Flutter → Maps SDK for Android → the restricted
/// Tirvona key works. Tiles appearing = key, package and SHA-1 all accepted;
/// a blank grey map means Google rejected the key (see logcat
/// "Authorization failure" for the package/SHA-1 it saw).
///
/// Opens on the Braj service area, then moves to the device's position once
/// a fix arrives (and shows the blue dot) if location access is granted.
class MapCheckScreen extends ConsumerStatefulWidget {
  const MapCheckScreen({super.key});

  @override
  ConsumerState<MapCheckScreen> createState() => _MapCheckScreenState();
}

class _MapCheckScreenState extends ConsumerState<MapCheckScreen> {
  static final _markers = {
    const Marker(
      markerId: MarkerId('service-area'),
      position: TirvonaMap.serviceAreaCenter,
      infoWindow: InfoWindow(title: 'Braj service area'),
    ),
  };

  GoogleMapController? _controller;
  bool _hasLocation = false;
  bool _locating = false;

  Future<void> _goToMyLocation({bool prompt = true}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final point = await ref
          .read(deviceLocationProvider)
          .currentPosition(prompt: prompt);
      if (!mounted) return;
      setState(() => _hasLocation = true);
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(point.latitude, point.longitude), 15),
      );
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          action: failure.needsSettings
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: () =>
                      ref.read(deviceLocationProvider).openSettings(failure),
                )
              : null,
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Maps check')),
      body: TirvonaMap(
        markers: _markers,
        showMyLocation: _hasLocation,
        onMapCreated: (controller) {
          _controller = controller;
          _goToMyLocation();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _locating ? null : _goToMyLocation,
        tooltip: 'My location',
        child: _locating
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location),
      ),
    );
  }
}
