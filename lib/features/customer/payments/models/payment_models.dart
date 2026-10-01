import '../../../rides/domain/ride_formatters.dart';
import '../../../rides/domain/ride_models.dart';

double _double(Object? value) => (value as num?)?.toDouble() ?? 0;
int _int(Object? value) => (value as num?)?.round() ?? 0;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// Mirrors the backend `PaymentStatus` (the payment record, aligned with
/// Razorpay). The apps mostly branch on [RidePaymentStatus] instead.
enum PaymentStatus {
  created('CREATED'),
  authorized('AUTHORIZED'),
  captured('CAPTURED'),
  failed('FAILED'),
  refunded('REFUNDED'),
  partiallyRefunded('PARTIALLY_REFUNDED');

  const PaymentStatus(this.wireName);

  final String wireName;

  static PaymentStatus fromWire(String? value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => PaymentStatus.created,
  );

  bool get isPaid =>
      this == captured || this == refunded || this == partiallyRefunded;

  String get label => switch (this) {
    created => 'Pending',
    authorized => 'Confirming',
    captured => 'Paid',
    failed => 'Failed',
    refunded => 'Refunded',
    partiallyRefunded => 'Partly refunded',
  };
}

/// One Tirvona payment (`PaymentView`). Amounts are rupees.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.rideId,
    required this.rideCode,
    required this.amount,
    required this.currency,
    required this.status,
    required this.ridePaymentStatus,
    required this.createdAt,
    this.gateway = 'RAZORPAY',
    this.method,
    this.methodDetail,
    this.razorpayOrderId,
    this.razorpayPaymentId,
    this.failureReason,
    this.paidAt,
    this.refundAmount,
    this.refundPending = 0,
    this.rideType,
    this.pickupAddress,
    this.destinationAddress,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    final details = _map(json['methodDetails']);
    final refund = _map(json['refund']);
    return PaymentRecord(
      id: json['id'] as String,
      rideId: json['rideId'] as String,
      rideCode: json['rideCode'] as String? ?? '',
      amount: _double(json['amount']),
      currency: json['currency'] as String? ?? 'INR',
      status: PaymentStatus.fromWire(json['status'] as String?),
      ridePaymentStatus: RidePaymentStatus.fromWire(
        json['ridePaymentStatus'] as String?,
      ),
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      gateway: json['gateway'] as String? ?? 'RAZORPAY',
      method: json['method'] as String?,
      methodDetail: details == null
          ? null
          : [
              details['bank'],
              details['wallet'],
              details['cardNetwork'],
              if (details['cardLast4'] != null) '•••• ${details['cardLast4']}',
            ].whereType<String>().where((part) => part.isNotEmpty).join(' · '),
      razorpayOrderId: json['razorpayOrderId'] as String?,
      razorpayPaymentId: json['razorpayPaymentId'] as String?,
      failureReason: json['failureReason'] as String?,
      paidAt: _date(json['paidAt']),
      refundAmount: refund == null ? null : _double(refund['amount']),
      refundPending: refund == null ? 0 : _double(refund['pending']),
      rideType: json['rideType'] as String?,
      pickupAddress: json['pickupAddress'] as String?,
      destinationAddress: json['destinationAddress'] as String?,
    );
  }

  final String id;
  final String rideId;
  final String rideCode;
  final double amount;
  final String currency;
  final PaymentStatus status;
  final RidePaymentStatus ridePaymentStatus;
  final DateTime createdAt;

  /// RAZORPAY, or CASH when the customer paid the driver directly.
  final String gateway;

  /// "cash", or as reported by Razorpay (upi, card, netbanking, wallet…).
  final String? method;
  final String? methodDetail;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final String? failureReason;
  final DateTime? paidAt;
  /// Refunded so far (processed by Razorpay).
  final double? refundAmount;

  /// Refunds on their way (accepted, not processed yet).
  final double refundPending;

  bool get hasRefund => (refundAmount ?? 0) > 0 || refundPending > 0;

  // History items only.
  final String? rideType;
  final String? pickupAddress;
  final String? destinationAddress;

  bool get isCash => gateway == 'CASH';

  String get methodLabel {
    final name = method == null && !isCash
        ? '—'
        : isCash
        ? 'Cash to driver'
        : RideFormat.paymentMethod(method);
    final detail = methodDetail;
    return detail == null || detail.isEmpty ? name : '$name ($detail)';
  }
}

/// Options for Razorpay Standard Checkout, exactly as the server issued
/// them. The amount is the server's — the app never computes it.
class CheckoutOptions {
  const CheckoutOptions({
    required this.key,
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.name,
    required this.description,
    this.prefillName,
    this.prefillContact,
    this.prefillEmail,
    this.notes = const {},
  });

  factory CheckoutOptions.fromJson(Map<String, dynamic> json) {
    final prefill = _map(json['prefill']) ?? const {};
    return CheckoutOptions(
      key: json['key'] as String,
      orderId: json['orderId'] as String,
      amountPaise: _int(json['amount']),
      currency: json['currency'] as String? ?? 'INR',
      name: json['name'] as String? ?? 'Tirvona Rides',
      description: json['description'] as String? ?? '',
      prefillName: prefill['name'] as String?,
      prefillContact: prefill['contact'] as String?,
      prefillEmail: prefill['email'] as String?,
      notes: (_map(json['notes']) ?? const {}).map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  final String key;
  final String orderId;
  final int amountPaise;
  final String currency;
  final String name;
  final String description;
  final String? prefillName;
  final String? prefillContact;
  final String? prefillEmail;
  final Map<String, String> notes;

  /// The map `Razorpay.open` expects.
  Map<String, dynamic> toRazorpayOptions() => {
    'key': key,
    'order_id': orderId,
    'amount': amountPaise,
    'currency': currency,
    'name': name,
    'description': description,
    'prefill': {
      if (prefillName != null) 'name': prefillName,
      if (prefillContact != null) 'contact': prefillContact,
      if (prefillEmail != null) 'email': prefillEmail,
    },
    'notes': notes,
    'theme': {'color': '#E67E22'},
    // Close the sheet on its own after 10 minutes of inactivity.
    'timeout': 600,
  };
}

/// `POST /payments/create`.
class PaymentCheckout {
  const PaymentCheckout({required this.payment, required this.options});

  factory PaymentCheckout.fromJson(
    Map<String, dynamic> json,
  ) => PaymentCheckout(
    payment: PaymentRecord.fromJson(json['payment'] as Map<String, dynamic>),
    options: CheckoutOptions.fromJson(json['checkout'] as Map<String, dynamic>),
  );

  final PaymentRecord payment;
  final CheckoutOptions options;
}

/// Mirrors the backend `RefundStatus` as the customer sees it.
enum RefundState {
  processing('PENDING', 'Processing'),
  refunded('PROCESSED', 'Refunded');

  const RefundState(this.wireName, this.label);

  final String wireName;
  final String label;

  static RefundState fromWire(String? value) =>
      value == refunded.wireName ? refunded : processing;
}

/// One refund on the receipt (never failed attempts or admin notes).
class CustomerRefund {
  const CustomerRefund({
    required this.id,
    required this.amount,
    required this.state,
    required this.reason,
    required this.createdAt,
    this.reference,
    this.processedAt,
  });

  factory CustomerRefund.fromJson(Map<String, dynamic> json) => CustomerRefund(
    id: json['id'] as String,
    amount: _double(json['amount']),
    state: RefundState.fromWire(json['status'] as String?),
    reason: json['reason'] as String? ?? 'Refund',
    createdAt: _date(json['createdAt']) ?? DateTime.now(),
    reference: json['reference'] as String?,
    processedAt: _date(json['processedAt']),
  );

  final String id;
  final double amount;
  final RefundState state;

  /// Customer wording from the server ("Fare adjustment").
  final String reason;
  final DateTime createdAt;

  /// Bank reference (ARN / RRN) the customer can quote to their bank.
  final String? reference;
  final DateTime? processedAt;
}

/// `GET /payments/:id` — the in-app receipt.
class PaymentReceipt {
  const PaymentReceipt({
    required this.payment,
    required this.rideCode,
    required this.rideType,
    required this.pickup,
    required this.destination,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.fare,
    required this.customerName,
    this.completedAt,
    this.driverName,
    this.vehicle,
    this.refunds = const [],
  });

  factory PaymentReceipt.fromJson(Map<String, dynamic> json) {
    final ride = json['ride'] as Map<String, dynamic>;
    final vehicle = _map(json['vehicle']);
    return PaymentReceipt(
      payment: PaymentRecord.fromJson(json),
      rideCode: ride['rideCode'] as String? ?? '',
      rideType: RideTypeCode.fromWire(ride['rideType'] as String? ?? 'AUTO'),
      pickup: Place.fromJson(ride['pickup'] as Map<String, dynamic>),
      destination: Place.fromJson(ride['destination'] as Map<String, dynamic>),
      distanceMeters: _int(ride['distanceMeters']),
      durationSeconds: _int(ride['durationSeconds']),
      fare: FareBreakdown.fromJson(ride['fare'] as Map<String, dynamic>),
      completedAt: _date(ride['completedAt']),
      customerName:
          (_map(json['customer']) ?? const {})['name'] as String? ?? '',
      driverName: _map(json['driver'])?['name'] as String?,
      vehicle: vehicle == null ? null : RideVehicleInfo.fromJson(vehicle),
      refunds: (json['refunds'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CustomerRefund.fromJson)
          .toList(),
    );
  }

  final PaymentRecord payment;
  final String rideCode;
  final RideTypeCode rideType;
  final Place pickup;
  final Place destination;
  final int distanceMeters;
  final int durationSeconds;
  final FareBreakdown fare;
  final DateTime? completedAt;
  final String customerName;
  final String? driverName;
  final RideVehicleInfo? vehicle;
  final List<CustomerRefund> refunds;
}

class PaymentHistoryPage {
  const PaymentHistoryPage({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  factory PaymentHistoryPage.fromJson(Map<String, dynamic> json) =>
      PaymentHistoryPage(
        items: (json['items'] as List<dynamic>)
            .map((item) => PaymentRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
        page: _int(json['page']),
        hasMore: json['hasMore'] as bool? ?? false,
      );

  final List<PaymentRecord> items;
  final int page;
  final bool hasMore;
}
