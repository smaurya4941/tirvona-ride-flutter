double _double(Object? value) => (value as num?)?.toDouble() ?? 0;
int _int(Object? value) => (value as num?)?.round() ?? 0;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

/// Mirrors the backend `EarningStatus`.
enum EarningStatus {
  pending('PENDING', 'Pending'),
  available('AVAILABLE', 'Available'),
  paid('PAID', 'Paid'),

  /// A cash ride: the driver already holds the fare; nothing is paid out.
  collected('COLLECTED', 'Cash collected');

  const EarningStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  static EarningStatus fromWire(String? value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => EarningStatus.pending,
  );
}

/// Mirrors the backend `PaymentMode`: who received the customer's money.
enum PaymentMode {
  online('ONLINE'),
  cash('CASH');

  const PaymentMode(this.wireName);

  final String wireName;

  static PaymentMode fromWire(String? value) =>
      value == cash.wireName ? cash : online;
}

/// Mirrors the backend `AdjustmentStatus` of a refund deduction.
enum AdjustmentStatus {
  outstanding('OUTSTANDING', 'To be deducted'),
  settled('SETTLED', 'Deducted'),
  waived('WAIVED', 'Waived');

  const AdjustmentStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  static AdjustmentStatus fromWire(String? value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => AdjustmentStatus.outstanding,
  );
}

/// The driver's share of a customer refund, deducted from a later payout.
/// Computed at the ride's own commission rate. Rupees.
class EarningAdjustment {
  const EarningAdjustment({
    required this.id,
    required this.earningId,
    required this.rideCode,
    required this.reason,
    required this.refundAmount,
    required this.commissionReversal,
    required this.amount,
    required this.commissionRate,
    required this.status,
    required this.createdAt,
    this.settledAt,
  });

  factory EarningAdjustment.fromJson(Map<String, dynamic> json) =>
      EarningAdjustment(
        id: json['id'] as String,
        earningId: json['earningId'] as String? ?? '',
        rideCode: json['rideCode'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        refundAmount: _double(json['refundAmount']),
        commissionReversal: _double(json['commissionReversal']),
        amount: _double(json['amount']),
        commissionRate: _double(json['commissionRate']),
        status: AdjustmentStatus.fromWire(json['status'] as String?),
        createdAt: _date(json['createdAt']) ?? DateTime.now(),
        settledAt: _date(json['settledAt']),
      );

  final String id;
  final String earningId;
  final String rideCode;

  /// Backend RefundReason (FARE_ADJUSTMENT, RIDE_CANCELLED, …).
  final String reason;

  /// What the customer got back.
  final double refundAmount;

  /// Tirvona's commission returned on the refunded part.
  final double commissionReversal;

  /// Deducted from the driver.
  final double amount;
  final double commissionRate;
  final AdjustmentStatus status;
  final DateTime createdAt;
  final DateTime? settledAt;

  String get reasonLabel => switch (reason) {
    'FARE_ADJUSTMENT' => 'Fare adjustment',
    'RIDE_CANCELLED' => 'Ride cancelled',
    'ADMIN_REFUND' => 'Refund by Tirvona',
    'CUSTOMER_SUPPORT' => 'Customer support',
    'EXTERNAL' => 'Refund',
    _ => 'Customer refund',
  };
}

List<EarningAdjustment> _adjustments(Object? value) => value is List
    ? value
          .whereType<Map<String, dynamic>>()
          .map(EarningAdjustment.fromJson)
          .toList()
    : const [];

enum EarningsPeriod {
  today('today', 'Today'),
  week('week', 'This week'),
  month('month', 'This month'),
  all('all', 'All');

  const EarningsPeriod(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// One ledger line: what the customer paid, Tirvona's commission (at the
/// rate captured when it was recorded) and the driver's share. Rupees.
class Earning {
  const Earning({
    required this.id,
    required this.rideId,
    required this.rideCode,
    required this.rideType,
    required this.rideCompletedAt,
    required this.grossFare,
    required this.commissionRate,
    required this.commissionAmount,
    required this.netEarning,
    required this.status,
    required this.availableAt,
    this.paymentMode = PaymentMode.online,
    this.paymentMethod,
    this.pickupAddress,
    this.destinationAddress,
    this.paidAt,
    this.payoutReference,
    this.payoutNote,
    this.adjustments = const [],
  });

  factory Earning.fromJson(Map<String, dynamic> json) => Earning(
    id: json['id'] as String,
    rideId: json['rideId'] as String,
    rideCode: json['rideCode'] as String? ?? '',
    rideType: json['rideType'] as String? ?? '',
    rideCompletedAt: _date(json['rideCompletedAt']) ?? DateTime.now(),
    grossFare: _double(json['grossFare']),
    commissionRate: _double(json['commissionRate']),
    commissionAmount: _double(json['commissionAmount']),
    netEarning: _double(json['netEarning']),
    status: EarningStatus.fromWire(json['status'] as String?),
    availableAt: _date(json['availableAt']) ?? DateTime.now(),
    paymentMode: PaymentMode.fromWire(json['paymentMode'] as String?),
    paymentMethod: json['paymentMethod'] as String?,
    pickupAddress: json['pickupAddress'] as String?,
    destinationAddress: json['destinationAddress'] as String?,
    paidAt: _date(json['paidAt']),
    payoutReference: json['payoutReference'] as String?,
    payoutNote: json['payoutNote'] as String?,
    adjustments: _adjustments(json['adjustments']),
  );

  final String id;
  final String rideId;
  final String rideCode;
  final String rideType;
  final DateTime rideCompletedAt;
  final double grossFare;
  final double commissionRate;
  final double commissionAmount;
  final double netEarning;
  final EarningStatus status;
  final DateTime availableAt;

  /// Cash: the customer paid the driver directly.
  final PaymentMode paymentMode;

  /// "cash", or Razorpay's method (upi, card…).
  final String? paymentMethod;
  final String? pickupAddress;
  final String? destinationAddress;
  final DateTime? paidAt;
  final String? payoutReference;
  final String? payoutNote;

  /// Refund deductions on this ride (detail view only).
  final List<EarningAdjustment> adjustments;

  /// Deducted or still to be deducted (a waived deduction costs nothing).
  double get deducted => adjustments
      .where((adjustment) => adjustment.status != AdjustmentStatus.waived)
      .fold(0, (sum, adjustment) => sum + adjustment.amount);
}

class EarningsWindow {
  const EarningsWindow({
    required this.net,
    required this.gross,
    required this.commission,
    required this.rides,
  });

  factory EarningsWindow.fromJson(Object? value) {
    final json = _map(value);
    return EarningsWindow(
      net: _double(json['net']),
      gross: _double(json['gross']),
      commission: _double(json['commission']),
      rides: _int(json['rides']),
    );
  }

  final double net;
  final double gross;
  final double commission;
  final int rides;
}

class EarningsSummary {
  const EarningsSummary({
    required this.today,
    required this.week,
    required this.month,
    required this.total,
    required this.pending,
    required this.available,
    required this.paid,
    this.collected = 0,
    this.commissionDue = 0,
    this.deductions = 0,
  });

  factory EarningsSummary.fromJson(Map<String, dynamic> json) {
    final balances = _map(json['balances']);
    return EarningsSummary(
      today: EarningsWindow.fromJson(json['today']),
      week: EarningsWindow.fromJson(json['week']),
      month: EarningsWindow.fromJson(json['month']),
      total: EarningsWindow.fromJson(json['total']),
      pending: _double(balances['pending']),
      available: _double(balances['available']),
      paid: _double(balances['paid']),
      collected: _double(balances['collected']),
      commissionDue: _double(balances['commissionDue']),
      deductions: _double(balances['deductions']),
    );
  }

  final EarningsWindow today;
  final EarningsWindow week;
  final EarningsWindow month;
  final EarningsWindow total;
  final double pending;
  final double available;
  final double paid;

  /// Driver's share of cash fares, already in hand (never paid out).
  final double collected;

  /// Tirvona's commission on cash fares, owed by the driver.
  final double commissionDue;

  /// Refund deductions still to come off the next payout.
  final double deductions;
}

/// `GET /earnings` — summary + one page of the ledger for a period.
class EarningsPage {
  const EarningsPage({
    required this.summary,
    required this.periodTotals,
    required this.items,
    required this.page,
    required this.hasMore,
    this.adjustments = const [],
  });

  factory EarningsPage.fromJson(Map<String, dynamic> json) => EarningsPage(
    adjustments: _adjustments(json['adjustments']),
    summary: EarningsSummary.fromJson(_map(json['summary'])),
    periodTotals: EarningsWindow.fromJson(json['periodTotals']),
    items: (json['items'] as List<dynamic>)
        .map((item) => Earning.fromJson(item as Map<String, dynamic>))
        .toList(),
    page: _int(json['page']),
    hasMore: json['hasMore'] as bool? ?? false,
  );

  final EarningsSummary summary;
  final EarningsWindow periodTotals;
  final List<Earning> items;
  final int page;
  final bool hasMore;

  /// Recent refund deductions (first page only).
  final List<EarningAdjustment> adjustments;
}
