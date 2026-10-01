import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/maps/map_marker_icons.dart';
import '../../../../core/maps/tirvona_map.dart';
import '../../../../core/theme/app_colors.dart';
import '../../application/nearby_drivers.dart';
import '../../domain/nearby_driver.dart';
import '../../domain/ride_models.dart';

/// Street-level zoom for the Home map.
const _homeZoom = 15.0;

/// The rider Home map: the pickup (named in a callout) and the free cars
/// around it, refreshed from `GET /rides/nearby-drivers`.
class HomeMap extends ConsumerStatefulWidget {
  const HomeMap({
    super.key,
    required this.pickup,
    required this.fallbackCenter,
    this.showMyLocation = false,
    this.padding = EdgeInsets.zero,
  });

  final Place? pickup;

  /// Where to look before a pickup is known (the device's last fix).
  final LatLng? fallbackCenter;
  final bool showMyLocation;
  final EdgeInsets padding;

  @override
  ConsumerState<HomeMap> createState() => HomeMapState();
}

class HomeMapState extends ConsumerState<HomeMap> {
  GoogleMapController? _controller;
  BitmapDescriptor? _pickupIcon;
  final _vehicleIcons = <String, BitmapDescriptor>{};
  double? _iconPixelRatio;

  static const _pickupMarker = MarkerId('pickup');

  LatLng get _center {
    final pickup = widget.pickup;
    if (pickup != null) return LatLng(pickup.latitude, pickup.longitude);
    return widget.fallbackCenter ?? TirvonaMap.serviceAreaCenter;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_loadIcons());
  }

  @override
  void didUpdateWidget(HomeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moved = oldWidget.pickup == null
        ? widget.pickup != null
        : widget.pickup == null || !oldWidget.pickup!.sameSpot(widget.pickup!);
    if (moved || oldWidget.fallbackCenter != widget.fallbackCenter) recenter();
  }

  /// Glides back to the pickup (after "locate me" or a new pickup).
  void recenter() {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller
          .animateCamera(CameraUpdate.newLatLngZoom(_center, _homeZoom))
          .then((_) => _showPickupCallout()),
    );
  }

  Future<void> _showPickupCallout() async {
    if (widget.pickup == null) return;
    try {
      await _controller?.showMarkerInfoWindow(_pickupMarker);
    } on Object {
      // The marker may not be on the map yet; the callout is cosmetic.
    }
  }

  Future<void> _loadIcons() async {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (ratio == _iconPixelRatio) return;
    _iconPixelRatio = ratio;
    try {
      final pickup = await MapMarkerIcons.place(
        color: const Color(0xFF2563EB),
        icon: Icons.my_location,
        devicePixelRatio: ratio,
        size: 40,
      );
      final vehicles = <String, BitmapDescriptor>{};
      for (final type in _VehicleStyle.all.keys) {
        final style = _VehicleStyle.of(type);
        vehicles[type] = await MapMarkerIcons.vehicle(
          color: style.color,
          icon: style.icon,
          devicePixelRatio: ratio,
          size: 40,
        );
      }
      if (!mounted) return;
      setState(() {
        _pickupIcon = pickup;
        _vehicleIcons
          ..clear()
          ..addAll(vehicles);
      });
    } on Object {
      // Default pins until next time; the map stays usable.
      _iconPixelRatio = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickup = widget.pickup;
    final drivers = pickup == null
        ? const <NearbyDriver>[]
        : ref
                  .watch(
                    nearbyDriversProvider(
                      nearbyDriversArea(pickup.latitude, pickup.longitude),
                    ),
                  )
                  .value ??
              const <NearbyDriver>[];

    final markers = <Marker>{
      if (pickup != null)
        Marker(
          markerId: _pickupMarker,
          position: LatLng(pickup.latitude, pickup.longitude),
          icon: _pickupIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: pickup.title),
          zIndexInt: 2,
        ),
      for (final (index, driver) in drivers.indexed)
        Marker(
          markerId: MarkerId('car-$index'),
          position: LatLng(driver.latitude, driver.longitude),
          icon:
              _vehicleIcons[_VehicleStyle.key(driver.vehicleType)] ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          flat: true,
          consumeTapEvents: true,
        ),
    };

    return TirvonaMap(
      initialCamera: CameraPosition(target: _center, zoom: _homeZoom),
      markers: markers,
      padding: widget.padding,
      showMyLocation: widget.showMyLocation,
      onMapCreated: (controller) {
        _controller = controller;
        unawaited(_showPickupCallout());
      },
    );
  }
}

/// Marker colour and glyph per vehicle type (`BIKE`, `AUTO`, …).
class _VehicleStyle {
  const _VehicleStyle(this.color, this.icon);

  final Color color;
  final IconData icon;

  static const all = <String, _VehicleStyle>{
    'BIKE': _VehicleStyle(Color(0xFF0F766E), Icons.two_wheeler),
    'AUTO': _VehicleStyle(Color(0xFFCA8A04), Icons.electric_rickshaw),
    'E_RICKSHAW': _VehicleStyle(Color(0xFF16A34A), Icons.electric_rickshaw),
    'CAB': _VehicleStyle(AppColors.midnightBlue, Icons.directions_car),
  };

  static String key(String? vehicleType) =>
      all.containsKey(vehicleType) ? vehicleType! : 'CAB';

  static _VehicleStyle of(String vehicleType) => all[key(vehicleType)]!;
}
