import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/maps/map_marker_icons.dart';
import '../../../../core/maps/polyline.dart';
import '../../../../core/maps/tirvona_map.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/live_tracking.dart';
import '../../domain/ride_models.dart';

/// What the map should frame.
enum RideMapStage {
  /// Pickup → destination (searching, finished rides).
  overview,

  /// Driver → pickup.
  approach,

  /// Driver → destination.
  trip,
}

/// An intermediate stop drawn on the map (circuit stops), marked done or not.
@immutable
class RideMapStop {
  const RideMapStop({
    required this.place,
    required this.label,
    this.done = false,
  });

  final Place place;
  final String label;
  final bool done;
}

/// Colour and glyph of a pickup/destination marker.
@immutable
class RideMapPin {
  const RideMapPin(this.color, this.icon);

  final Color color;
  final IconData icon;

  @override
  bool operator ==(Object other) =>
      other is RideMapPin && other.color == color && other.icon == icon;

  @override
  int get hashCode => Object.hash(color, icon);
}

LatLng _latLng(Place place) => LatLng(place.latitude, place.longitude);

const _pickupId = MarkerId('pickup');
const _destinationId = MarkerId('destination');
const _driverId = MarkerId('driver');
const _routeId = PolylineId('route');
const _approachId = PolylineId('approach');

/// Live ride map (Google Maps): pickup, destination, route line and the
/// driver's marker.
///
/// The map itself stays still while the driver moves — only the driver
/// marker animates to each new position and heading. The camera is refitted
/// when the [stage] changes, when the driver first appears, or when the
/// rider taps "recenter"; never on every location update, so panning around
/// is not fought by the app.
///
/// Route lines follow the roads when the server has a road path (Google
/// Routes): [routePolyline] for pickup → destination and [liveRoute] for the
/// driver's current leg. Without one (straight-line fallback) the line is
/// drawn straight between the two ends, dashed for the driver's leg.
class RideMap extends StatefulWidget {
  const RideMap({
    super.key,
    required this.pickup,
    required this.destination,
    required this.stage,
    this.driver,
    this.driverIcon = Icons.navigation,
    this.padding = const EdgeInsets.all(48),
    this.routePolyline,
    this.liveRoute,
    this.pickupStyle = const RideMapPin(
      AppColors.success,
      Icons.person_pin_circle,
    ),
    this.destinationStyle = const RideMapPin(AppColors.bhagwa, Icons.flag),
    this.refitSignal = 0,
    this.stops = const [],
  });

  final Place pickup;
  final Place destination;
  final RideMapStage stage;
  final DriverPosition? driver;
  final IconData driverIcon;

  /// Pickup → destination road path from booking (encoded polyline).
  final String? routePolyline;

  /// The driver's current leg from `GET /rides/:id/route`; used only while
  /// its stage matches [stage].
  final LiveRoute? liveRoute;

  /// Space to keep clear around fitted points (e.g. under a bottom sheet).
  /// Also moves the Google logo above whatever covers the map's bottom.
  final EdgeInsets padding;

  final RideMapPin pickupStyle;
  final RideMapPin destinationStyle;

  /// Bump to re-frame the map (a "recenter" button).
  final int refitSignal;

  /// Circuit stops between the pickup and the destination, in order. Shown
  /// as numbered markers and framed in the overview.
  final List<RideMapStop> stops;

  @override
  State<RideMap> createState() => _RideMapState();
}

class _RideMapState extends State<RideMap> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addListener(() => setState(() {}));

  GoogleMapController? _controller;
  LatLng? _from;
  LatLng? _to;
  double _headingFrom = 0;
  double _headingTo = 0;

  BitmapDescriptor _pickupIcon = BitmapDescriptor.defaultMarkerWithHue(
    BitmapDescriptor.hueGreen,
  );
  BitmapDescriptor _destinationIcon = BitmapDescriptor.defaultMarkerWithHue(
    BitmapDescriptor.hueOrange,
  );
  BitmapDescriptor? _driverBitmap;
  double? _iconPixelRatio;
  IconData? _driverBitmapIcon;
  (RideMapPin, RideMapPin)? _loadedPins;

  @override
  void initState() {
    super.initState();
    final driver = widget.driver;
    if (driver != null) {
      _from = _to = LatLng(driver.latitude, driver.longitude);
      _headingFrom = _headingTo = driver.heading ?? 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIcons();
  }

  @override
  void didUpdateWidget(RideMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final driver = widget.driver;
    final driverAppeared = oldWidget.driver == null && driver != null;

    if (driver != null && !identical(driver, oldWidget.driver)) {
      final target = LatLng(driver.latitude, driver.longitude);
      // Start from wherever the marker is drawn right now.
      _from = _currentPosition ?? target;
      _headingFrom = _currentHeading;
      _to = target;
      _headingTo = driver.heading ?? _headingTo;
      _motion.forward(from: 0);
    }
    if (oldWidget.driverIcon != widget.driverIcon ||
        oldWidget.pickupStyle != widget.pickupStyle ||
        oldWidget.destinationStyle != widget.destinationStyle) {
      _loadIcons();
    }
    // The first road path of a leg can bend well outside the straight-line
    // frame; fit once when it arrives (not on every refresh).
    final roadPathArrived =
        _liveRouteFor(oldWidget)?.followsRoads != true &&
            _activeLiveRoute?.followsRoads == true ||
        oldWidget.routePolyline == null &&
            widget.routePolyline != null &&
            widget.stage == RideMapStage.overview;
    if (oldWidget.stage != widget.stage ||
        driverAppeared ||
        roadPathArrived ||
        oldWidget.padding != widget.padding ||
        oldWidget.refitSignal != widget.refitSignal ||
        !oldWidget.pickup.sameSpot(widget.pickup) ||
        !oldWidget.destination.sameSpot(widget.destination)) {
      _fit();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  /// Rasterises the marker badges for this screen's pixel ratio (cached
  /// process-wide); default pins are shown until they are ready.
  Future<void> _loadIcons() async {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (ratio == _iconPixelRatio &&
        widget.driverIcon == _driverBitmapIcon &&
        _loadedPins == (widget.pickupStyle, widget.destinationStyle)) {
      return;
    }
    _iconPixelRatio = ratio;
    final driverIcon = _driverBitmapIcon = widget.driverIcon;
    final pins = _loadedPins = (widget.pickupStyle, widget.destinationStyle);
    try {
      final icons = await Future.wait([
        MapMarkerIcons.place(
          color: pins.$1.color,
          icon: pins.$1.icon,
          devicePixelRatio: ratio,
        ),
        MapMarkerIcons.place(
          color: pins.$2.color,
          icon: pins.$2.icon,
          devicePixelRatio: ratio,
        ),
        MapMarkerIcons.vehicle(
          color: AppColors.midnightBlue,
          icon: driverIcon,
          devicePixelRatio: ratio,
        ),
      ]);
      if (!mounted || driverIcon != widget.driverIcon) return;
      setState(() {
        _pickupIcon = icons[0];
        _destinationIcon = icons[1];
        _driverBitmap = icons[2];
      });
    } on Object {
      // Keep the default pins; the map stays usable.
      _iconPixelRatio = null;
    }
  }

  double get _t => Curves.easeInOut.transform(_motion.value);

  LatLng? get _currentPosition {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return to;
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * _t,
      from.longitude + (to.longitude - from.longitude) * _t,
    );
  }

  /// Interpolates along the shortest arc (350° → 10° turns 20°, not 340°).
  double get _currentHeading {
    final delta = ((_headingTo - _headingFrom + 540) % 360) - 180;
    return (_headingFrom + delta * _t) % 360;
  }

  // Decoded paths, memoised per encoded string (rebuilds run every frame
  // while the driver marker animates).
  String? _bookingEncoded;
  List<LatLng> _bookingPoints = const [];
  String? _liveEncoded;
  List<LatLng> _livePoints = const [];

  /// Pickup → destination along the roads; empty when only straight.
  List<LatLng> get _bookingPath {
    if (widget.routePolyline != _bookingEncoded) {
      _bookingEncoded = widget.routePolyline;
      _bookingPoints = decodePolyline(_bookingEncoded);
    }
    return _bookingPoints;
  }

  /// The live leg's road path, only while it belongs to the current stage.
  List<LatLng> get _livePath {
    final live = _activeLiveRoute;
    final encoded = live?.followsRoads == true ? live!.polyline : null;
    if (encoded != _liveEncoded) {
      _liveEncoded = encoded;
      _livePoints = decodePolyline(encoded);
    }
    return _livePoints;
  }

  LiveRoute? get _activeLiveRoute => _liveRouteFor(widget);

  static LiveRoute? _liveRouteFor(RideMap map) {
    final live = map.liveRoute;
    final expected = switch (map.stage) {
      RideMapStage.approach => LiveRouteStage.approach,
      RideMapStage.trip => LiveRouteStage.trip,
      RideMapStage.overview => null,
    };
    return live != null && live.stage == expected ? live : null;
  }

  List<LatLng> get _focusPoints {
    final driver = _to;
    return switch (widget.stage) {
      RideMapStage.overview => [
        _latLng(widget.pickup),
        _latLng(widget.destination),
        for (final stop in widget.stops) _latLng(stop.place),
        ..._bookingPath,
      ],
      RideMapStage.approach => [_latLng(widget.pickup), ?driver, ..._livePath],
      RideMapStage.trip => [_latLng(widget.destination), ?driver, ..._livePath],
    };
  }

  /// The camera before the first fit: the middle of what will be framed.
  CameraPosition get _initialCamera {
    final bounds = boundsAround(_focusPoints);
    return CameraPosition(
      target: LatLng(
        (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
        (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
      ),
      zoom: 13,
    );
  }

  /// Frames [_focusPoints] inside the padded viewport. Safe to call before
  /// the map exists (no-op) or before it has a size (retried next frame).
  void _fit() {
    final controller = _controller;
    if (controller == null) return;
    final update = CameraUpdate.newLatLngBounds(boundsAround(_focusPoints), 0);
    unawaited(
      controller.animateCamera(update).catchError((Object _) {
        // "Map size can't be 0" right after creation: retry once laid out.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(controller, _controller)) {
            unawaited(controller.moveCamera(update).catchError((Object _) {}));
          }
        });
      }),
    );
  }

  Set<Marker> get _markers {
    final pickup = widget.pickup;
    final destination = widget.destination;
    final driver = _currentPosition;
    final driverBitmap = _driverBitmap;
    return {
      Marker(
        markerId: _pickupId,
        position: _latLng(pickup),
        icon: _pickupIcon,
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(title: 'Pickup', snippet: pickup.title),
        zIndexInt: 1,
      ),
      Marker(
        markerId: _destinationId,
        position: _latLng(destination),
        icon: _destinationIcon,
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(
          title: 'Destination',
          snippet: destination.title,
        ),
        zIndexInt: 1,
      ),
      for (final (index, stop) in widget.stops.indexed)
        Marker(
          markerId: MarkerId('stop-$index'),
          position: _latLng(stop.place),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            stop.done ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
          ),
          alpha: stop.done ? 0.6 : 1,
          infoWindow: InfoWindow(
            title: stop.label,
            snippet: stop.place.address,
          ),
        ),
      if (driver != null)
        Marker(
          markerId: _driverId,
          position: driver,
          icon:
              driverBitmap ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          // Flat + rotation turns the north-pointing glyph to the heading.
          flat: driverBitmap != null,
          rotation: driverBitmap != null && widget.driver?.heading != null
              ? _currentHeading
              : 0,
          anchor: driverBitmap != null
              ? const Offset(0.5, 0.5)
              : const Offset(0.5, 1),
          infoWindow: const InfoWindow(title: 'Driver'),
          zIndexInt: 2,
        ),
    };
  }

  Set<Polyline> get _polylines {
    final pickup = _latLng(widget.pickup);
    final destination = _latLng(widget.destination);
    final driver = _currentPosition;
    final booking = _bookingPath;
    final live = _livePath;
    final onTrip = widget.stage == RideMapStage.trip;

    // On the trip, the driver's live road path replaces the booked one.
    final followsRoads = (onTrip && live.isNotEmpty) || booking.isNotEmpty;
    final tripPath = onTrip && live.isNotEmpty
        ? live
        : booking.isNotEmpty
        ? booking
        : [pickup, destination];
    return {
      Polyline(
        polylineId: _routeId,
        points: tripPath,
        width: 5,
        color: onTrip
            ? AppColors.bhagwa
            : AppColors.midnightBlue.withValues(alpha: 0.55),
        // Only a straight fallback needs the great-circle treatment.
        geodesic: !followsRoads,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
      if (widget.stage == RideMapStage.approach && live.isNotEmpty)
        Polyline(
          polylineId: _approachId,
          points: live,
          width: 5,
          color: AppColors.midnightBlue,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 1,
        )
      else if (driver != null && widget.stage == RideMapStage.approach)
        // No road path yet: a dashed straight hint.
        Polyline(
          polylineId: _approachId,
          points: [driver, pickup],
          width: 4,
          color: AppColors.midnightBlue,
          patterns: [PatternItem.dash(20), PatternItem.gap(14)],
          geodesic: true,
          zIndex: 1,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        TirvonaMap(
          initialCamera: _initialCamera,
          markers: _markers,
          polylines: _polylines,
          padding: widget.padding,
          minZoom: 4,
          maxZoom: 19,
          onMapCreated: (controller) {
            _controller = controller;
            WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
          },
        ),
        Positioned(
          right: 12,
          top: 12,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: 'Recenter',
              backgroundColor: Colors.white,
              foregroundColor: AppColors.midnightBlue,
              onPressed: _fit,
              child: const Icon(Icons.center_focus_strong),
            ),
          ),
        ),
      ],
    );
  }
}
