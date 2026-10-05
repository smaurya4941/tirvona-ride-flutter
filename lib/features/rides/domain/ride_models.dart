import 'package:flutter/foundation.dart';

import '../../circuit/domain/circuit_models.dart';

/// Mirrors the backend's `RideStatus` (rides/ride-state-machine.ts). The
/// server owns every transition; the app only renders the current value.
enum RideStatus {
  searching('SEARCHING'),
  driverAssigned('DRIVER_ASSIGNED'),
  driverAccepted('DRIVER_ACCEPTED'),
  driverArrived('DRIVER_ARRIVED'),
  rideStarted('RIDE_STARTED'),
  completed('COMPLETED'),
  cancelled('CANCELLED'),
  noDriverAvailable('NO_DRIVER_AVAILABLE');

  const RideStatus(this.wireName);

  final String wireName;

  static RideStatus fromWire(String value) => values.firstWhere(
    (status) => status.wireName == value,
    // An unknown future status is safest treated as "still going".
    orElse: () => RideStatus.searching,
  );

  bool get isTerminal =>
      this == completed || this == cancelled || this == noDriverAvailable;

  bool get isActive => !isTerminal;

  /// Customer may cancel until the trip starts (server: CUSTOMER_CANCELLABLE).
  bool get customerCanCancel =>
      this == searching ||
      this == driverAssigned ||
      this == driverAccepted ||
      this == driverArrived;

  /// Driver may cancel once committed, before starting (server: DRIVER_CANCELLABLE).
  bool get driverCanCancel => this == driverAccepted || this == driverArrived;

  String get label => switch (this) {
    searching => 'Searching',
    driverAssigned => 'Driver assigned',
    driverAccepted => 'Driver on the way',
    driverArrived => 'Driver arrived',
    rideStarted => 'On trip',
    completed => 'Completed',
    cancelled => 'Cancelled',
    noDriverAvailable => 'No driver found',
  };
}

/// Mirrors the backend's `RidePaymentStatus` (rides/ride-payment-status.ts):
/// the money side of a ride, separate from [RideStatus]. A completed ride is
/// financially closed only once this is [success].
enum RidePaymentStatus {
  notRequired('NOT_REQUIRED'),
  pending('PENDING'),
  orderCreated('ORDER_CREATED'),
  processing('PROCESSING'),
  success('SUCCESS'),
  failed('FAILED'),
  cancelled('CANCELLED'),
  refunded('REFUNDED'),
  partiallyRefunded('PARTIALLY_REFUNDED');

  const RidePaymentStatus(this.wireName);

  final String wireName;

  static RidePaymentStatus fromWire(String? value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => RidePaymentStatus.notRequired,
  );

  /// The customer still owes the fare and may (re)start a payment.
  bool get isPayable =>
      this == pending ||
      this == orderCreated ||
      this == processing ||
      this == failed;

  bool get isPaid =>
      this == success || this == refunded || this == partiallyRefunded;

  String get label => switch (this) {
    notRequired => 'Nothing due',
    pending => 'Payment pending',
    orderCreated => 'Payment pending',
    processing => 'Confirming payment',
    success => 'Paid',
    failed => 'Payment failed',
    cancelled => 'Written off',
    refunded => 'Refunded',
    partiallyRefunded => 'Partly refunded',
  };
}

/// Summary of the ride's payment as the ride view carries it.
/// The server's payment `method` for a ride paid to the driver in cash.
const cashPaymentMethod = 'cash';

class RidePaymentInfo {
  const RidePaymentInfo({
    required this.paymentId,
    this.gatewayPaymentId,
    this.method,
    this.amount,
    this.paidAt,
    this.failureReason,
  });

  factory RidePaymentInfo.fromJson(Map<String, dynamic> json) =>
      RidePaymentInfo(
        paymentId: json['paymentId'] as String,
        gatewayPaymentId: json['gatewayPaymentId'] as String?,
        method: json['method'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        paidAt: _date(json['paidAt']),
        failureReason: json['failureReason'] as String?,
      );

  /// Tirvona payment id (receipt: `GET /payments/:id`).
  final String paymentId;

  /// Razorpay payment id (pay_…).
  final String? gatewayPaymentId;

  /// "cash", or Razorpay's method (upi, card, netbanking, wallet…).
  final String? method;
  final double? amount;
  final DateTime? paidAt;
  final String? failureReason;

  /// Paid to the driver in cash rather than through Razorpay.
  bool get isCash => method == cashPaymentMethod;
}

/// A bookable product (`GET /ride-types`). Codes are data on the server
/// since Phase 7 — admins can add products such as CAB_XL — so this is a
/// value type, not an enum: an unknown code is kept as-is rather than being
/// mistaken for another ride type.
@immutable
class RideTypeCode {
  const RideTypeCode._(this.wireName, this.label);

  static const bike = RideTypeCode._('BIKE', 'Bike');
  static const auto = RideTypeCode._('AUTO', 'Auto');
  static const eRickshaw = RideTypeCode._('E_RICKSHAW', 'E-Rickshaw');
  static const cab = RideTypeCode._('CAB', 'Cab');

  /// The V1 products, in the order the app offers them.
  static const values = [bike, auto, eRickshaw, cab];

  final String wireName;

  /// Fallback name; the server's displayName is preferred where available.
  final String label;

  static RideTypeCode fromWire(String value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return RideTypeCode._(value, _labelFor(value));
  }

  /// "CAB_XL" → "Cab Xl".
  static String _labelFor(String code) => code
      .toLowerCase()
      .split('_')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');

  @override
  bool operator ==(Object other) =>
      other is RideTypeCode && other.wireName == wireName;

  @override
  int get hashCode => wireName.hashCode;

  @override
  String toString() => wireName;
}

double _double(Object? value) => (value as num?)?.toDouble() ?? 0;
int _int(Object? value) => (value as num?)?.round() ?? 0;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// A named point: pickup, destination or a driver's position.
@immutable
class Place {
  const Place({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.name,
  });

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    address: json['address'] as String,
    latitude: _double(json['latitude']),
    longitude: _double(json['longitude']),
  );

  /// Short label for lists; falls back to the address.
  final String? name;
  final String address;
  final double latitude;
  final double longitude;

  String get title => name ?? address;

  Map<String, dynamic> toJson() => {
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
  };

  bool sameSpot(Place other) =>
      (latitude - other.latitude).abs() < 1e-6 &&
      (longitude - other.longitude).abs() < 1e-6;

  @override
  bool operator ==(Object other) =>
      other is Place && other.address == address && sameSpot(other);

  @override
  int get hashCode => Object.hash(address, latitude, longitude);
}

/// The peak-hour slot that raised a fare's per-km rate. Decided by the
/// server; the app only shows it.
class PeakFare {
  const PeakFare({
    required this.name,
    required this.hikePercent,
    this.startTime,
    this.endTime,
    this.surcharge = 0,
  });

  factory PeakFare.fromJson(Map<String, dynamic> json) => PeakFare(
    name: json['name'] as String? ?? 'Peak pricing',
    hikePercent: _double(json['hikePercent']),
    startTime: json['startTime'] as String?,
    endTime: json['endTime'] as String?,
    surcharge: _double(json['surcharge']),
  );

  final String name;
  final double hikePercent;
  final String? startTime;
  final String? endTime;

  /// Extra distance charge caused by the peak, rupees.
  final double surcharge;

  /// "+50%" / "+12.5%".
  String get hikeLabel {
    final text = hikePercent == hikePercent.roundToDouble()
        ? hikePercent.toStringAsFixed(0)
        : hikePercent.toString();
    return '+$text%';
  }
}

class FareBreakdown {
  const FareBreakdown({
    required this.currency,
    required this.baseFare,
    required this.perKmRate,
    this.basePerKmRate,
    this.peak,
    required this.perMinuteRate,
    required this.minimumFare,
    required this.distanceCharge,
    required this.timeCharge,
    required this.subtotal,
    required this.minimumFareApplied,
    required this.estimatedFare,
    this.finalFare,
    this.discount,
    this.payableFare,
    this.finalBill,
  });

  factory FareBreakdown.fromJson(Map<String, dynamic> json) => FareBreakdown(
    finalBill: json['final'] is Map<String, dynamic>
        ? FinalFareBill.fromJson(json['final'] as Map<String, dynamic>)
        : null,
    currency: json['currency'] as String? ?? 'INR',
    baseFare: _double(json['baseFare']),
    perKmRate: _double(json['perKmRate']),
    basePerKmRate: (json['basePerKmRate'] as num?)?.toDouble(),
    peak: json['peak'] is Map<String, dynamic>
        ? PeakFare.fromJson(json['peak'] as Map<String, dynamic>)
        : null,
    perMinuteRate: _double(json['perMinuteRate']),
    minimumFare: _double(json['minimumFare']),
    distanceCharge: _double(json['distanceCharge']),
    timeCharge: _double(json['timeCharge']),
    subtotal: _double(json['subtotal']),
    minimumFareApplied: json['minimumFareApplied'] as bool? ?? false,
    estimatedFare: _double(json['estimatedFare']),
    finalFare: (json['finalFare'] as num?)?.toDouble(),
    discount: (json['discount'] as num?)?.toDouble(),
    payableFare: (json['payableFare'] as num?)?.toDouble(),
  );

  final String currency;
  final double baseFare;

  /// What the trip is charged per km: the base rate, or the peak rate while
  /// [peak] is set.
  final double perKmRate;

  /// The permanent per-km rate (null from servers without peak pricing).
  final double? basePerKmRate;

  /// Set when a peak-hour slot raised the per-km rate for this fare.
  final PeakFare? peak;
  final double perMinuteRate;
  final double minimumFare;
  final double distanceCharge;
  final double timeCharge;
  final double subtotal;
  final bool minimumFareApplied;
  final double estimatedFare;
  final double? finalFare;

  /// Promo discount (estimate until the ride completes). Funded by Tirvona.
  final double? discount;

  /// What the customer pays after the discount; null when no promo applies.
  final double? payableFare;

  /// The bill frozen at completion (actual trip); null until completed, and
  /// on rides completed before it existed.
  final FinalFareBill? finalBill;

  /// The trip fare before any discount: final once known, else the estimate.
  double get fare => finalFare ?? estimatedFare;

  /// What the customer pays: after any promo discount.
  double get payable => payableFare ?? fare;

  bool get hasDiscount => (discount ?? 0) > 0;

  bool get isPeak => peak != null;
}

/// The final bill as the server priced it at completion: the trip measured
/// (GPS trail or the booked route) and each component. Rupees.
class FinalFareBill {
  const FinalFareBill({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.distanceMeasured,
    required this.durationMeasured,
    required this.baseFare,
    required this.distanceCharge,
    required this.timeCharge,
    required this.minimumFareApplied,
    required this.capApplied,
    required this.total,
    required this.payable,
  });

  factory FinalFareBill.fromJson(Map<String, dynamic> json) => FinalFareBill(
    distanceMeters: (json['distanceMeters'] as num?)?.round() ?? 0,
    durationSeconds: (json['durationSeconds'] as num?)?.round() ?? 0,
    distanceMeasured: json['distanceSource'] == 'ACTUAL',
    durationMeasured: json['durationSource'] == 'ACTUAL',
    baseFare: _double(json['baseFare']),
    distanceCharge: _double(json['distanceCharge']),
    timeCharge: _double(json['timeCharge']),
    minimumFareApplied: json['minimumFareApplied'] as bool? ?? false,
    capApplied: json['capApplied'] as bool? ?? false,
    total: _double(json['total']),
    payable: _double(json['payable']),
  );

  final int distanceMeters;
  final int durationSeconds;

  /// Billed on the GPS trail (false: the booked route).
  final bool distanceMeasured;

  /// Billed on the actual trip time (false: the booked estimate).
  final bool durationMeasured;
  final double baseFare;
  final double distanceCharge;
  final double timeCharge;
  final bool minimumFareApplied;

  /// Limited to 1.5 × the estimate the customer accepted.
  final bool capApplied;
  final double total;
  final double payable;
}

/// A bookable product as `GET /ride-types` lists it.
class RideTypeInfo {
  const RideTypeInfo({
    required this.code,
    required this.displayName,
    required this.icon,
    this.description,
  });

  factory RideTypeInfo.fromJson(Map<String, dynamic> json) => RideTypeInfo(
    code: RideTypeCode.fromWire(json['code'] as String),
    displayName: json['displayName'] as String? ?? json['code'] as String,
    icon: json['icon'] as String? ?? '',
    description: json['description'] as String?,
  );

  final RideTypeCode code;
  final String displayName;
  final String icon;
  final String? description;
}

/// Server-priced quote for one ride type (`POST /rides/estimate[/all]`).
class FareEstimate {
  const FareEstimate({
    required this.rideType,
    required this.displayName,
    required this.icon,
    required this.seatCapacity,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.fare,
    this.description,
    this.routePolyline,
    this.pickupEtaSeconds,
    this.driversNearby = 0,
  });

  factory FareEstimate.fromJson(Map<String, dynamic> json) => FareEstimate(
    rideType: RideTypeCode.fromWire(json['rideType'] as String),
    displayName: json['displayName'] as String,
    description: json['description'] as String?,
    icon: json['icon'] as String? ?? '',
    seatCapacity: _int(json['seatCapacity']),
    distanceMeters: _int(json['distanceMeters']),
    durationSeconds: _int(json['durationSeconds']),
    fare: FareBreakdown.fromJson(json['fare'] as Map<String, dynamic>),
    routePolyline: json['routePolyline'] as String?,
    pickupEtaSeconds: (json['pickupEtaSeconds'] as num?)?.toInt(),
    driversNearby: (json['driversNearby'] as num?)?.toInt() ?? 0,
  );

  final RideTypeCode rideType;
  final String displayName;
  final String? description;
  final String icon;
  final int seatCapacity;
  final int distanceMeters;
  final int durationSeconds;
  final FareBreakdown fare;

  /// Road path of the quoted trip (Google encoded polyline); null when the
  /// server fell back to a straight-line estimate.
  final String? routePolyline;

  /// How soon the nearest free driver could reach the pickup; null when no
  /// driver of this vehicle type is nearby right now (booking still works,
  /// dispatch keeps looking).
  final int? pickupEtaSeconds;

  /// Free drivers of this vehicle type near the pickup.
  final int driversNearby;
}

class RideVehicleInfo {
  const RideVehicleInfo({
    required this.vehicleType,
    required this.registrationNumber,
    this.make,
    this.model,
    this.color,
  });

  factory RideVehicleInfo.fromJson(Map<String, dynamic> json) =>
      RideVehicleInfo(
        vehicleType: json['vehicleType'] as String? ?? '',
        registrationNumber: json['registrationNumber'] as String? ?? '',
        make: json['make'] as String?,
        model: json['model'] as String?,
        color: json['color'] as String?,
      );

  final String vehicleType;
  final String registrationNumber;
  final String? make;
  final String? model;
  final String? color;

  String get description => [
    color,
    make,
    model,
  ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
}

/// A position of the driver: from the ride view (last known) or a live
/// `ride.location_updated` event.
@immutable
class DriverPosition {
  const DriverPosition({
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    this.heading,
    this.speed,
  });

  factory DriverPosition.fromJson(Map<String, dynamic> json) => DriverPosition(
    latitude: _double(json['latitude']),
    longitude: _double(json['longitude']),
    heading: (json['heading'] as num?)?.toDouble(),
    speed: (json['speed'] as num?)?.toDouble(),
    updatedAt:
        _date(json['updatedAt']) ?? _date(json['recordedAt']) ?? DateTime.now(),
  );

  final double latitude;
  final double longitude;

  /// Degrees clockwise from north, when the device reported one.
  final double? heading;

  /// Metres per second.
  final double? speed;
  final DateTime updatedAt;
}

class RideDriverInfo {
  const RideDriverInfo({
    required this.name,
    required this.phone,
    required this.ratingAverage,
    required this.totalRides,
    this.vehicle,
    this.location,
  });

  factory RideDriverInfo.fromJson(Map<String, dynamic> json) => RideDriverInfo(
    name: json['name'] as String? ?? 'Your driver',
    phone: json['phone'] as String? ?? '',
    ratingAverage: _double(json['ratingAverage']),
    totalRides: _int(json['totalRides']),
    vehicle: _map(json['vehicle']) == null
        ? null
        : RideVehicleInfo.fromJson(_map(json['vehicle'])!),
    location: _map(json['location']) == null
        ? null
        : DriverPosition.fromJson(_map(json['location'])!),
  );

  final String name;
  final String phone;
  final double ratingAverage;
  final int totalRides;
  final RideVehicleInfo? vehicle;

  /// Last known position once the driver has accepted.
  final DriverPosition? location;
}

class RideCustomerInfo {
  const RideCustomerInfo({required this.name, this.phone});

  factory RideCustomerInfo.fromJson(Map<String, dynamic> json) =>
      RideCustomerInfo(
        name: json['name'] as String? ?? 'Customer',
        phone: json['phone'] as String?,
      );

  final String name;

  /// Shared by the server only after the driver has accepted.
  final String? phone;
}

class RideOtp {
  const RideOtp({required this.code, this.expiresAt});

  factory RideOtp.fromJson(Map<String, dynamic> json) => RideOtp(
    code: json['code'] as String,
    expiresAt: _date(json['expiresAt']),
  );

  final String code;
  final DateTime? expiresAt;
}

class RideCancellation {
  const RideCancellation({
    required this.cancelledBy,
    this.reason,
    this.reasonCode,
    this.feeAmount = 0,
    this.feeStatus,
  });

  factory RideCancellation.fromJson(Map<String, dynamic> json) =>
      RideCancellation(
        cancelledBy: json['cancelledBy'] as String? ?? 'SYSTEM',
        reason: json['reason'] as String?,
        reasonCode: json['reasonCode'] as String?,
        feeAmount: _double(json['feeAmount']),
        feeStatus: json['feeStatus'] as String?,
      );

  /// CUSTOMER | DRIVER | ADMIN | SYSTEM
  final String cancelledBy;
  final String? reason;
  final String? reasonCode;

  /// Cancellation fee assessed by the server (rupees), 0 when none.
  final double feeAmount;

  /// NOT_APPLICABLE | DUE | WAIVED | COLLECTED
  final String? feeStatus;

  bool get hasFee => feeAmount > 0;

  String get feeLabel => switch (feeStatus) {
    'DUE' => 'due',
    'WAIVED' => 'waived',
    'COLLECTED' => 'paid',
    _ => '',
  };
}

/// The promo applied to a ride at booking (`ride.promo`).
class RidePromoInfo {
  const RidePromoInfo({
    required this.code,
    required this.title,
    required this.discount,
  });

  factory RidePromoInfo.fromJson(Map<String, dynamic> json) => RidePromoInfo(
    code: json['code'] as String? ?? '',
    title: json['title'] as String? ?? '',
    discount: _double(json['discount']),
  );

  final String code;
  final String title;
  final double discount;
}

/// A ride as the server shows it to the current user. The customer view
/// carries [driver] and [otp]; the driver view carries [customer],
/// [assignmentExpiresAt] and [pickupDistanceMeters]. History items carry
/// neither.
class Ride {
  const Ride({
    required this.id,
    required this.rideCode,
    required this.status,
    this.stateVersion = 0,
    required this.rideType,
    required this.pickup,
    required this.destination,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.fare,
    required this.requestedAt,
    this.assignedAt,
    this.acceptedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.expiredAt,
    this.searchExpiresAt,
    this.cancellation,
    this.driver,
    this.otp,
    this.customer,
    this.assignmentExpiresAt,
    this.pickupDistanceMeters,
    this.paymentStatus = RidePaymentStatus.notRequired,
    this.payment,
    this.promo,
    this.zoneName,
    this.routePolyline,
    this.circuit,
  });

  factory Ride.fromJson(Map<String, dynamic> json) => Ride(
    id: json['id'] as String,
    rideCode: json['rideCode'] as String,
    status: RideStatus.fromWire(json['status'] as String),
    stateVersion: _int(json['stateVersion']),
    rideType: RideTypeCode.fromWire(json['rideType'] as String),
    pickup: Place.fromJson(json['pickup'] as Map<String, dynamic>),
    destination: Place.fromJson(json['destination'] as Map<String, dynamic>),
    distanceMeters: _int(json['distanceMeters']),
    durationSeconds: _int(json['durationSeconds']),
    fare: FareBreakdown.fromJson(json['fare'] as Map<String, dynamic>),
    requestedAt: _date(json['requestedAt']) ?? DateTime.now(),
    assignedAt: _date(json['assignedAt']),
    acceptedAt: _date(json['acceptedAt']),
    arrivedAt: _date(json['arrivedAt']),
    startedAt: _date(json['startedAt']),
    completedAt: _date(json['completedAt']),
    cancelledAt: _date(json['cancelledAt']),
    expiredAt: _date(json['expiredAt']),
    searchExpiresAt: _date(json['searchExpiresAt']),
    cancellation: _map(json['cancellation']) == null
        ? null
        : RideCancellation.fromJson(_map(json['cancellation'])!),
    driver: _map(json['driver']) == null
        ? null
        : RideDriverInfo.fromJson(_map(json['driver'])!),
    otp: _map(json['otp']) == null
        ? null
        : RideOtp.fromJson(_map(json['otp'])!),
    customer: _map(json['customer']) == null
        ? null
        : RideCustomerInfo.fromJson(_map(json['customer'])!),
    assignmentExpiresAt: _date(json['assignmentExpiresAt']),
    pickupDistanceMeters: (json['pickupDistanceMeters'] as num?)?.round(),
    paymentStatus: RidePaymentStatus.fromWire(json['paymentStatus'] as String?),
    payment: _map(json['payment']) == null
        ? null
        : RidePaymentInfo.fromJson(_map(json['payment'])!),
    promo: _map(json['promo']) == null
        ? null
        : RidePromoInfo.fromJson(_map(json['promo'])!),
    zoneName: _map(json['zone'])?['name'] as String?,
    routePolyline: json['routePolyline'] as String?,
    // Only circuit rides carry it (kind == CIRCUIT).
    circuit: json['kind'] == 'CIRCUIT' && _map(json['circuit']) != null
        ? CircuitInfo.fromJson(_map(json['circuit'])!)
        : null,
  );

  final String id;
  final String rideCode;
  final RideStatus status;

  /// Monotonic per ride; a snapshot with a lower value is older and ignored.
  final int stateVersion;
  final RideTypeCode rideType;
  final Place pickup;
  final Place destination;
  final int distanceMeters;
  final int durationSeconds;
  final FareBreakdown fare;
  final DateTime requestedAt;
  final DateTime? assignedAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? expiredAt;
  final DateTime? searchExpiresAt;
  final RideCancellation? cancellation;
  final RideDriverInfo? driver;
  final RideOtp? otp;
  final RideCustomerInfo? customer;
  final DateTime? assignmentExpiresAt;
  final int? pickupDistanceMeters;

  /// Money state (Phase 4); only meaningful once [status] is completed.
  final RidePaymentStatus paymentStatus;
  final RidePaymentInfo? payment;

  /// Promo applied at booking (Phase 7).
  final RidePromoInfo? promo;

  /// The service zone of the pickup, when zones are in force.
  final String? zoneName;

  /// Pickup → destination road path at booking (Google encoded polyline,
  /// see core/maps/polyline.dart); null for straight-line estimates.
  final String? routePolyline;

  /// Set on a Tirvona Circuit (a multi-stop package): its stops, usage and
  /// running bill. Null for a normal pickup → destination ride.
  final CircuitInfo? circuit;

  bool get isCircuit => circuit != null;

  /// Completed, and the customer still owes the final fare.
  bool get awaitsPayment =>
      status == RideStatus.completed && paymentStatus.isPayable;
}

class RidePage {
  const RidePage({
    required this.items,
    required this.page,
    required this.total,
    required this.hasMore,
  });

  factory RidePage.fromJson(Map<String, dynamic> json) => RidePage(
    items: (json['items'] as List<dynamic>)
        .map((item) => Ride.fromJson(item as Map<String, dynamic>))
        .toList(),
    page: _int(json['page']),
    total: _int(json['total']),
    hasMore: json['hasMore'] as bool? ?? false,
  );

  final List<Ride> items;
  final int page;
  final int total;
  final bool hasMore;
}

/// `PATCH /drivers/availability` and `GET /drivers/dashboard`.
class DriverDashboard {
  const DriverDashboard({
    required this.isOnline,
    required this.isAvailable,
    required this.totalRides,
    required this.ratingAverage,
    required this.todayRides,
    required this.todayFares,
    required this.pendingRequests,
    this.todayEarnings = 0,
    this.todayPaidRides = 0,
    this.locationFresh = false,
    this.location,
    this.vehicle,
    this.currentRide,
  });

  factory DriverDashboard.fromJson(Map<String, dynamic> json) {
    final today = _map(json['today']) ?? const {};
    final location = _map(json['location']);
    final vehicle = _map(json['vehicle']);
    return DriverDashboard(
      isOnline: json['isOnline'] as bool? ?? false,
      isAvailable: json['isAvailable'] as bool? ?? false,
      totalRides: _int(json['totalRides']),
      ratingAverage: _double(json['ratingAverage']),
      todayRides: _int(today['completedRides']),
      todayFares: _double(today['grossFares']),
      todayEarnings: _double(today['earnings']),
      todayPaidRides: _int(today['paidRides']),
      pendingRequests: _int(json['pendingRequests']),
      locationFresh: json['locationFresh'] as bool? ?? false,
      location: location == null
          ? null
          : Place(
              address: 'Current location',
              latitude: _double(location['latitude']),
              longitude: _double(location['longitude']),
            ),
      vehicle: vehicle == null ? null : RideVehicleInfo.fromJson(vehicle),
      currentRide: _map(json['currentRide']) == null
          ? null
          : Ride.fromJson(_map(json['currentRide'])!),
    );
  }

  final bool isOnline;
  final bool isAvailable;
  final int totalRides;
  final double ratingAverage;
  final int todayRides;
  final double todayFares;
  final int pendingRequests;

  /// Net share of today's paid rides, from the earnings ledger.
  final double todayEarnings;
  final int todayPaidRides;

  /// Stored location recent enough for matching (server rule).
  final bool locationFresh;
  final Place? location;
  final RideVehicleInfo? vehicle;
  final Ride? currentRide;
}
