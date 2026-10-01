import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../theme/app_colors.dart';

/// Tirvona's Google Maps surface (Maps SDK for Android underneath); every
/// map in the app goes through this widget.
///
/// Only Android has a key configured (injected into AndroidManifest.xml from
/// android/secrets.properties, see app/build.gradle.kts). On other platforms,
/// and in widget tests, where the native SDK has no key or no platform view,
/// a placeholder is shown instead.
class TirvonaMap extends StatefulWidget {
  const TirvonaMap({
    super.key,
    this.initialCamera = const CameraPosition(
      target: serviceAreaCenter,
      zoom: 14,
    ),
    this.markers = const {},
    this.polylines = const {},
    this.padding = EdgeInsets.zero,
    this.minZoom = 4,
    this.maxZoom = 20,
    this.showMyLocation = false,
    this.onMapCreated,
    this.onCameraMoveStarted,
    this.onCameraMove,
    this.onCameraIdle,
    this.onTap,
  });

  /// Braj (Mathura–Vrindavan): where maps open when nothing better is known.
  static const serviceAreaCenter = LatLng(27.5714, 77.6716);

  final CameraPosition initialCamera;
  final Set<Marker> markers;
  final Set<Polyline> polylines;

  /// Viewport insets: keeps the Google logo, camera centre and fitted bounds
  /// clear of overlaid bars and bottom sheets.
  final EdgeInsets padding;
  final double minZoom;
  final double maxZoom;

  /// Draws the blue dot. The caller must already hold the location
  /// permission (see features/places/application/current_location.dart).
  final bool showMyLocation;

  final ValueChanged<GoogleMapController>? onMapCreated;
  final VoidCallback? onCameraMoveStarted;
  final ValueChanged<CameraPosition>? onCameraMove;
  final VoidCallback? onCameraIdle;
  final ValueChanged<LatLng>? onTap;

  /// Whether the native Google Maps SDK is wired up on this platform.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  State<TirvonaMap> createState() => _TirvonaMapState();
}

class _TirvonaMapState extends State<TirvonaMap> {
  GoogleMapController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!TirvonaMap.isSupported) return const _MapUnavailable();
    return GoogleMap(
      initialCameraPosition: widget.initialCamera,
      onMapCreated: (controller) {
        _controller = controller;
        widget.onMapCreated?.call(controller);
      },
      markers: widget.markers,
      polylines: widget.polylines,
      padding: widget.padding,
      minMaxZoomPreference: MinMaxZoomPreference(
        widget.minZoom,
        widget.maxZoom,
      ),
      myLocationEnabled: widget.showMyLocation,
      onCameraMoveStarted: widget.onCameraMoveStarted,
      onCameraMove: widget.onCameraMove,
      onCameraIdle: widget.onCameraIdle,
      onTap: widget.onTap,
      // Tirvona draws its own controls over the map.
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      buildingsEnabled: false,
      indoorViewEnabled: false,
      trafficEnabled: false,
    );
  }
}

class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceSand,
      child: Center(
        child: Text(
          'Map is available on Android only',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Bounds around [points], widened to [minSpan] degrees so a single point
/// (or two very close ones) is framed at street level rather than max zoom.
LatLngBounds boundsAround(Iterable<LatLng> points, {double minSpan = 0.008}) {
  var south = 90.0, west = 180.0, north = -90.0, east = -180.0;
  for (final point in points) {
    if (point.latitude < south) south = point.latitude;
    if (point.latitude > north) north = point.latitude;
    if (point.longitude < west) west = point.longitude;
    if (point.longitude > east) east = point.longitude;
  }
  final padLat = ((minSpan - (north - south)) / 2).clamp(0.0, minSpan);
  final padLng = ((minSpan - (east - west)) / 2).clamp(0.0, minSpan);
  return LatLngBounds(
    southwest: LatLng(south - padLat, west - padLng),
    northeast: LatLng(north + padLat, east + padLng),
  );
}
