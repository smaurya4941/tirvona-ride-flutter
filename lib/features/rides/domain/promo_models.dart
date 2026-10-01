import 'ride_models.dart';

/// `POST /promotions/validate` — the server's quote for a code on a trip.
/// Advisory until booking: the server validates and reserves it again then.
class PromoQuote {
  const PromoQuote({
    required this.code,
    required this.title,
    required this.rideType,
    required this.fare,
    required this.discount,
    required this.payableFare,
    this.description,
  });

  factory PromoQuote.fromJson(Map<String, dynamic> json) => PromoQuote(
    code: json['code'] as String,
    title: json['title'] as String? ?? '',
    description: json['description'] as String?,
    rideType: RideTypeCode.fromWire(json['rideType'] as String? ?? ''),
    fare: (json['fare'] as num?)?.toDouble() ?? 0,
    discount: (json['discount'] as num?)?.toDouble() ?? 0,
    payableFare: (json['payableFare'] as num?)?.toDouble() ?? 0,
  );

  final String code;
  final String title;
  final String? description;
  final RideTypeCode rideType;
  final double fare;
  final double discount;
  final double payableFare;
}

/// `GET /promotions` — live offers the app may list.
class PromoOffer {
  const PromoOffer({
    required this.code,
    required this.title,
    required this.discountType,
    required this.discountValue,
    required this.endsAt,
    this.description,
    this.maxDiscount,
    this.minRideValue,
    this.rideTypes = const [],
  });

  factory PromoOffer.fromJson(Map<String, dynamic> json) => PromoOffer(
    code: json['code'] as String,
    title: json['title'] as String? ?? '',
    description: json['description'] as String?,
    discountType: json['discountType'] as String? ?? 'FLAT',
    discountValue: (json['discountValue'] as num?)?.toDouble() ?? 0,
    maxDiscount: (json['maxDiscount'] as num?)?.toDouble(),
    minRideValue: (json['minRideValue'] as num?)?.toDouble(),
    rideTypes: (json['applicableRideTypes'] as List<dynamic>? ?? const [])
        .cast<String>(),
    endsAt:
        DateTime.tryParse(json['endsAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );

  final String code;
  final String title;
  final String? description;

  /// PERCENTAGE | FLAT
  final String discountType;
  final double discountValue;
  final double? maxDiscount;
  final double? minRideValue;

  /// Ride type codes; empty = every ride type.
  final List<String> rideTypes;
  final DateTime endsAt;

  String get summary {
    final value = discountValue % 1 == 0
        ? discountValue.toStringAsFixed(0)
        : discountValue.toStringAsFixed(2);
    final cap = maxDiscount == null
        ? ''
        : ' (up to ₹${maxDiscount!.toStringAsFixed(0)})';
    return discountType == 'PERCENTAGE' ? '$value% off$cap' : '₹$value off';
  }
}
