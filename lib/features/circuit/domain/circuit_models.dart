import 'package:flutter/foundation.dart';

import '../../rides/domain/ride_models.dart';

/// Tirvona Circuit: a predefined multi-stop package (stops, price, included
/// time and distance) booked with a vehicle and driver. Every value here is
/// computed by the server — the app never prices, orders stops or times a
/// circuit itself.

double _double(Object? value) => (value as num?)?.toDouble() ?? 0;
int _int(Object? value) => (value as num?)?.round() ?? 0;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;
List<Map<String, dynamic>> _list(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

/// A package stop: a place picked by Admin from the maps search.
@immutable
class CircuitStop {
  const CircuitStop({
    required this.order,
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  factory CircuitStop.fromJson(Map<String, dynamic> json) => CircuitStop(
    order: _int(json['order']),
    placeId: json['placeId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    address: json['address'] as String? ?? '',
    latitude: _double(json['latitude']),
    longitude: _double(json['longitude']),
  );

  final int order;
  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  Place get place => Place(
    name: name,
    address: address,
    latitude: latitude,
    longitude: longitude,
  );
}

/// The commercial terms of one vehicle on a package: the shared included
/// distance and time, plus that vehicle's price and extra rates.
@immutable
class CircuitPricing {
  const CircuitPricing({
    required this.basePrice,
    required this.includedDistanceMeters,
    required this.includedDurationSeconds,
    required this.extraDistanceRatePerKm,
    required this.extraDurationRatePerHour,
  });

  factory CircuitPricing.fromJson(Map<String, dynamic> json) => CircuitPricing(
    basePrice: _double(json['basePrice']),
    includedDistanceMeters: _int(json['includedDistanceMeters']),
    includedDurationSeconds: _int(json['includedDurationSeconds']),
    extraDistanceRatePerKm: _double(json['extraDistanceRatePerKm']),
    extraDurationRatePerHour: _double(json['extraDurationRatePerHour']),
  );

  final double basePrice;
  final int includedDistanceMeters;
  final int includedDurationSeconds;
  final double extraDistanceRatePerKm;
  final double extraDurationRatePerHour;
}

/// A vehicle the package can be booked with, and how many it may carry.
@immutable
class CircuitVehicleOption {
  const CircuitVehicleOption({
    required this.rideType,
    required this.displayName,
    required this.icon,
    required this.seatCapacity,
    required this.maxPassengers,
    required this.pricing,
  });

  factory CircuitVehicleOption.fromJson(Map<String, dynamic> json) =>
      CircuitVehicleOption(
        rideType: RideTypeCode.fromWire(json['rideType'] as String),
        displayName: json['displayName'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        seatCapacity: _int(json['seatCapacity']),
        maxPassengers: _int(json['maxPassengers']),
        pricing: CircuitPricing.fromJson(
          _map(json['pricing']) ?? const <String, dynamic>{},
        ),
      );

  final RideTypeCode rideType;
  final String displayName;
  final String icon;
  final int seatCapacity;

  /// The package limit capped by this vehicle's seats (server rule).
  final int maxPassengers;

  /// What the circuit costs with this vehicle (each vehicle is priced
  /// separately by Admin).
  final CircuitPricing pricing;
}

/// `GET /circuit-packages[/:id]`: what customers browse.
class CircuitPackage {
  const CircuitPackage({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.city,
    required this.stops,
    required this.pricing,
    required this.vehicles,
    required this.maxPassengers,
    required this.days,
    required this.opensAt,
    required this.closesAt,
    required this.availableNow,
    this.unavailableReason,
    this.validFrom,
    this.validUntil,
    this.cancellationPolicy,
    this.coverPath,
  });

  factory CircuitPackage.fromJson(Map<String, dynamic> json) {
    final availability = _map(json['availability']) ?? const {};
    return CircuitPackage(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      city: json['city'] as String? ?? '',
      stops: _list(json['stops']).map(CircuitStop.fromJson).toList(),
      pricing: CircuitPricing.fromJson(json['pricing'] as Map<String, dynamic>),
      vehicles: _list(json['vehicles'])
          .map(CircuitVehicleOption.fromJson)
          .toList(),
      maxPassengers: _int(json['maxPassengers']),
      days: (availability['days'] as List<dynamic>? ?? const [])
          .whereType<num>()
          .map((day) => day.toInt())
          .toList(),
      opensAt: availability['opensAt'] as String? ?? '',
      closesAt: availability['closesAt'] as String? ?? '',
      validFrom: availability['validFrom'] as String?,
      validUntil: availability['validUntil'] as String?,
      availableNow: json['availableNow'] as bool? ?? false,
      unavailableReason: json['unavailableReason'] as String?,
      cancellationPolicy: json['cancellationPolicy'] as String?,
      coverPath: json['coverPath'] as String?,
    );
  }

  final String id;
  final String code;
  final String name;
  final String description;
  final String city;
  final List<CircuitStop> stops;

  /// The cheapest vehicle's terms: the "from" price shown on lists.
  final CircuitPricing pricing;

  /// Cheapest first, each with its own [CircuitVehicleOption.pricing].
  final List<CircuitVehicleOption> vehicles;
  final int maxPassengers;

  /// True when the vehicles are not all the same price, so lists say "from".
  bool get hasPriceRange =>
      vehicles.map((vehicle) => vehicle.pricing.basePrice).toSet().length > 1;

  /// 0 = Monday … 6 = Sunday.
  final List<int> days;
  final String opensAt;
  final String closesAt;
  final String? validFrom;
  final String? validUntil;
  final bool availableNow;
  final String? unavailableReason;
  final String? cancellationPolicy;

  /// Relative to the API base (`/circuit-packages/:id/cover?v=…`).
  final String? coverPath;
}

/// `POST /circuit-rides/estimate`. An estimate, never the final fare.
class CircuitEstimate {
  const CircuitEstimate({
    required this.packageId,
    required this.packageName,
    required this.rideType,
    required this.rideTypeName,
    required this.passengers,
    required this.maxPassengers,
    required this.pickup,
    required this.stops,
    required this.routeDistanceMeters,
    required this.routeDurationSeconds,
    required this.pickupLegMeters,
    required this.legs,
    required this.pricing,
    required this.packagePrice,
    required this.estimatedTotal,
    required this.expectedExtraDistanceCharge,
    required this.expectedExtraDurationCharge,
    required this.notices,
    this.routePolyline,
    this.pickupEtaSeconds,
    this.driversNearby = 0,
    this.cancellationPolicy,
  });

  factory CircuitEstimate.fromJson(Map<String, dynamic> json) {
    final route = _map(json['route']) ?? const {};
    final fare = _map(json['fare']) ?? const {};
    final pkg = _map(json['package']) ?? const {};
    final rideType = _map(json['rideType']) ?? const {};
    return CircuitEstimate(
      packageId: pkg['id'] as String? ?? '',
      packageName: pkg['name'] as String? ?? '',
      rideType: RideTypeCode.fromWire(rideType['code'] as String? ?? ''),
      rideTypeName: rideType['displayName'] as String? ?? '',
      passengers: _int(json['passengers']),
      maxPassengers: _int(json['maxPassengers']),
      pickup: Place.fromJson(json['pickup'] as Map<String, dynamic>),
      stops: _list(json['stops']).map(CircuitStop.fromJson).toList(),
      routeDistanceMeters: _int(route['distanceMeters']),
      routeDurationSeconds: _int(route['durationSeconds']),
      pickupLegMeters: _int(_map(route['pickupLeg'])?['distanceMeters']),
      legs: _list(route['legs'])
          .map(
            (leg) => (
              from: leg['from'] as String? ?? '',
              to: leg['to'] as String? ?? '',
              distanceMeters: _int(leg['distanceMeters']),
              durationSeconds: _int(leg['durationSeconds']),
            ),
          )
          .toList(),
      routePolyline: route['polyline'] as String?,
      pricing: CircuitPricing.fromJson(json['pricing'] as Map<String, dynamic>),
      packagePrice: _double(fare['packagePrice']),
      estimatedTotal: _double(fare['estimatedTotal']),
      expectedExtraDistanceCharge: _double(fare['expectedExtraDistanceCharge']),
      expectedExtraDurationCharge: _double(fare['expectedExtraDurationCharge']),
      notices: (json['notices'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      pickupEtaSeconds: (json['pickupEtaSeconds'] as num?)?.toInt(),
      driversNearby: _int(json['driversNearby']),
      cancellationPolicy: json['cancellationPolicy'] as String?,
    );
  }

  final String packageId;
  final String packageName;
  final RideTypeCode rideType;
  final String rideTypeName;
  final int passengers;
  final int maxPassengers;
  final Place pickup;
  final List<CircuitStop> stops;

  /// Pickup → stop 1 → … → last stop.
  final int routeDistanceMeters;
  final int routeDurationSeconds;
  final int pickupLegMeters;
  final List<
    ({String from, String to, int distanceMeters, int durationSeconds})
  >
  legs;
  final String? routePolyline;
  final CircuitPricing pricing;
  final double packagePrice;

  /// Package price plus any extra the planned route already implies.
  final double estimatedTotal;
  final double expectedExtraDistanceCharge;
  final double expectedExtraDurationCharge;
  final List<String> notices;
  final int? pickupEtaSeconds;
  final int driversNearby;
  final String? cancellationPolicy;
}

/// Per-stop lifecycle, owned by the backend.
enum CircuitStopStatus {
  upcoming('UPCOMING'),
  arriving('ARRIVING'),
  arrived('ARRIVED'),
  waiting('WAITING'),
  completed('COMPLETED'),
  skipped('SKIPPED');

  const CircuitStopStatus(this.wireName);

  final String wireName;

  static CircuitStopStatus fromWire(String? value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => CircuitStopStatus.upcoming,
  );

  bool get isDone => this == completed || this == skipped;

  /// The driver is at the stop (arrived, or waiting while the customer visits).
  bool get isAtStop => this == arrived || this == waiting;

  String get label => switch (this) {
    upcoming => 'Upcoming',
    arriving => 'Heading there',
    arrived => 'Arrived',
    waiting => 'Visiting',
    completed => 'Visited',
    skipped => 'Skipped',
  };
}

/// One stop of a booked circuit, with this trip's progress.
@immutable
class CircuitRideStop {
  const CircuitRideStop({
    required this.stop,
    required this.status,
    this.arrivedAt,
    this.completedAt,
  });

  factory CircuitRideStop.fromJson(Map<String, dynamic> json) =>
      CircuitRideStop(
        stop: CircuitStop.fromJson(json),
        status: CircuitStopStatus.fromWire(json['status'] as String?),
        arrivedAt: _date(json['arrivedAt']),
        completedAt: _date(json['completedAt']),
      );

  final CircuitStop stop;
  final CircuitStopStatus status;
  final DateTime? arrivedAt;
  final DateTime? completedAt;

  int get order => stop.order;
  String get name => stop.name;
}

/// The running bill: package price plus extras so far (server-computed).
@immutable
class CircuitCharges {
  const CircuitCharges({
    required this.basePrice,
    required this.extraKm,
    required this.extraDistanceCharge,
    required this.extraBlocks,
    required this.extraDurationCharge,
    required this.total,
  });

  factory CircuitCharges.fromJson(Map<String, dynamic> json) => CircuitCharges(
    basePrice: _double(json['basePrice']),
    extraKm: _int(json['extraKm']),
    extraDistanceCharge: _double(json['extraDistanceCharge']),
    extraBlocks: _int(json['extraBlocks']),
    extraDurationCharge: _double(json['extraDurationCharge']),
    total: _double(json['total']),
  );

  final double basePrice;
  final int extraKm;
  final double extraDistanceCharge;
  final int extraBlocks;
  final double extraDurationCharge;
  final double total;

  bool get hasExtras => extraDistanceCharge > 0 || extraDurationCharge > 0;
}

/// `ride.circuit` on a circuit ride: package snapshot, stops and usage.
class CircuitInfo {
  const CircuitInfo({
    required this.packageId,
    required this.packageCode,
    required this.name,
    required this.city,
    required this.passengers,
    required this.stops,
    required this.currentStopOrder,
    required this.readyToComplete,
    required this.pricing,
    required this.distanceMeters,
    required this.distanceReliable,
    required this.elapsedSeconds,
    required this.serverTime,
    required this.projected,
    this.exceptionStopOrder,
    this.exceptionNote,
    this.cancellationPolicy,
    this.endedEarlyReason,
    this.settledExtraKm,
    this.settledExtraBlocks,
  });

  factory CircuitInfo.fromJson(Map<String, dynamic> json) {
    final usage = _map(json['usage']) ?? const {};
    final exception = _map(json['exception']);
    final settlement = _map(json['settlement']);
    return CircuitInfo(
      packageId: json['packageId'] as String? ?? '',
      packageCode: json['packageCode'] as String? ?? '',
      name: json['name'] as String? ?? 'Circuit',
      city: json['city'] as String? ?? '',
      passengers: _int(json['passengers']),
      stops: _list(json['stops']).map(CircuitRideStop.fromJson).toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      currentStopOrder: _int(json['currentStopOrder']),
      readyToComplete: json['readyToComplete'] as bool? ?? false,
      pricing: CircuitPricing.fromJson(
        _map(json['pricing']) ?? const <String, dynamic>{},
      ),
      distanceMeters: _int(usage['distanceMeters']),
      distanceReliable: usage['distanceReliable'] as bool? ?? true,
      elapsedSeconds: _int(usage['elapsedSeconds']),
      serverTime: _date(usage['serverTime']) ?? DateTime.now(),
      projected: CircuitCharges.fromJson(
        _map(json['projected']) ?? const <String, dynamic>{},
      ),
      exceptionStopOrder: exception == null
          ? null
          : _int(exception['stopOrder']),
      exceptionNote: exception?['note'] as String?,
      cancellationPolicy: json['cancellationPolicy'] as String?,
      endedEarlyReason: json['endedEarlyReason'] as String?,
      settledExtraKm: settlement == null ? null : _int(settlement['extraKm']),
      settledExtraBlocks: settlement == null
          ? null
          : _int(settlement['extraBlocks']),
    );
  }

  final String packageId;
  final String packageCode;
  final String name;
  final String city;
  final int passengers;
  final List<CircuitRideStop> stops;

  /// 0 before the start; stops.length + 1 once every stop is done.
  final int currentStopOrder;
  final bool readyToComplete;
  final CircuitPricing pricing;
  final int distanceMeters;
  final bool distanceReliable;

  /// Seconds since the start as of [serverTime]; tick locally from there.
  final int elapsedSeconds;
  final DateTime serverTime;
  final CircuitCharges projected;

  /// Set while a stop is reported blocked and support has not resolved it.
  final int? exceptionStopOrder;
  final String? exceptionNote;
  final String? cancellationPolicy;
  final String? endedEarlyReason;
  final int? settledExtraKm;
  final int? settledExtraBlocks;

  bool get hasException => exceptionStopOrder != null;

  CircuitRideStop? get currentStop {
    for (final stop in stops) {
      if (stop.order == currentStopOrder) return stop;
    }
    return null;
  }

  CircuitRideStop? get nextStop {
    for (final stop in stops) {
      if (stop.order == currentStopOrder + 1) return stop;
    }
    return null;
  }

  int get stopsDone => stops.where((stop) => stop.status.isDone).length;
}

/// Realtime events specific to circuits (mirrors `CircuitEvent` on the API).
abstract final class CircuitEvents {
  static const started = 'circuit.started';
  static const stopArrived = 'circuit.stop.arrived';
  static const stopCompleted = 'circuit.stop.completed';
  static const stopSkipped = 'circuit.stop.skipped';
  static const stopBlocked = 'circuit.stop.blocked';
  static const exceptionResolved = 'circuit.exception.resolved';
  static const nextStop = 'circuit.next_stop';
  static const usage = 'circuit.usage';
  static const timeWarning = 'circuit.time_warning';
  static const distanceWarning = 'circuit.distance_warning';
  static const completed = 'circuit.completed';
}

/// A circuit moment worth telling the user about (a snackbar), from a push.
@immutable
class CircuitNotice {
  const CircuitNotice({required this.event, required this.message});

  final String event;
  final String message;

  bool get isWarning =>
      event == CircuitEvents.timeWarning ||
      event == CircuitEvents.distanceWarning ||
      event == CircuitEvents.stopBlocked;

  /// Null for events that only refresh the screen.
  static CircuitNotice? fromEvent(
    String event,
    Map<String, dynamic> data, {
    required bool asDriver,
  }) {
    final stop = data['stopName'] as String?;
    final warning = data['warning'] as String?;
    final message = switch (event) {
      CircuitEvents.timeWarning => switch (warning) {
        'TIME_30_MIN' =>
          asDriver
              ? 'Package time remaining: 30 minutes.'
              : 'Your included circuit time ends in 30 minutes.',
        'TIME_10_MIN' => asDriver ? 'Package time remaining: 10 minutes.' : 'Your included time ends in 10 minutes. Extra time is charged after that.',
        _ => asDriver ? 'Included package time is over.' : 'Your included time is over. Additional time charges may apply.',
      },
      CircuitEvents.distanceWarning =>
        warning == 'DISTANCE_80' ? 'Most of the included distance is used.' : 'Included distance exhausted. Additional distance charges may apply.',
      CircuitEvents.stopArrived when !asDriver && stop != null =>
        'Arrived at $stop',
      CircuitEvents.nextStop when stop != null => 'Next stop: $stop',
      CircuitEvents.stopSkipped => 'A stop was skipped by Tirvona support.',
      CircuitEvents.stopBlocked =>
        asDriver
            ? 'Reported. Tirvona support will decide how to continue.'
            : 'Your driver reported a stop as unreachable. Support is on it.',
      CircuitEvents.exceptionResolved =>
        'Support resolved the issue. Carry on.',
      _ => null,
    };
    return message == null
        ? null
        : CircuitNotice(event: event, message: message);
  }
}

/// Stable formatting for circuit screens.
abstract final class CircuitFormat {
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// "5 hours", "4.5 hours", "45 min".
  static String includedTime(int seconds) {
    if (seconds < 3600) return '${(seconds / 60).round()} min';
    final hours = seconds / 3600;
    final text = hours == hours.roundToDouble()
        ? hours.toStringAsFixed(0)
        : hours.toStringAsFixed(1);
    return '$text ${hours == 1 ? 'hour' : 'hours'}';
  }

  /// "2h 14m" (negative: "−0h 12m").
  static String clock(int seconds) {
    final negative = seconds < 0;
    final total = seconds.abs() ~/ 60;
    final text = '${total ~/ 60}h ${(total % 60).toString().padLeft(2, '0')}m';
    return negative ? '−$text' : text;
  }

  /// "17.4 km"
  static String km(int meters) => '${(meters / 1000).toStringAsFixed(1)} km';

  /// "30 km"
  static String includedKm(int meters) {
    final km = meters / 1000;
    return '${km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toStringAsFixed(1)} km';
  }

  /// "Every day", "Mon–Fri", "Sat, Sun".
  static String days(List<int> days) {
    final sorted = [...days]..sort();
    if (sorted.length == 7) return 'Every day';
    if (sorted.isEmpty) return 'Not running';
    final consecutive =
        sorted.length > 2 && sorted.last - sorted.first == sorted.length - 1;
    if (consecutive) {
      return '${weekdays[sorted.first]}–${weekdays[sorted.last]}';
    }
    return sorted.map((day) => weekdays[day]).join(', ');
  }
}
