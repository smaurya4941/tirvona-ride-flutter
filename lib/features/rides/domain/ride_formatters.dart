import 'ride_models.dart';

/// Display helpers kept free of `intl` so the app adds no dependency for
/// three formats.
abstract final class RideFormat {
  /// ₹120, ₹22.50
  static String money(double value) {
    final whole = value == value.roundToDouble();
    return '₹${whole ? value.round().toString() : value.toStringAsFixed(2)}';
  }

  /// How a ride was paid: "Cash", "UPI", "Card"… ("Online" when unknown).
  static String paymentMethod(String? method) => switch (method) {
    cashPaymentMethod => 'Cash',
    'upi' => 'UPI',
    'card' => 'Card',
    'netbanking' => 'Net banking',
    'wallet' => 'Wallet',
    'emi' => 'EMI',
    null || '' => 'Online',
    final other => other.toUpperCase(),
  };

  /// 850 m, 3.2 km
  static String distance(int meters) {
    if (meters < 1000) return '${(meters / 10).round() * 10} m';
    return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';
  }

  /// 1 min, 14 min, 1 h 5 min
  static String duration(int seconds) {
    final minutes = (seconds / 60).round().clamp(1, 1 << 30);
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours h' : '$hours h $rest min';
  }

  /// 09:41
  static String time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// 24 Sep 2026
  static String date(DateTime value) =>
      '${value.day} ${_months[value.month - 1]} ${value.year}';

  /// 23 Sep, 09:41
  static String dateTime(DateTime value) =>
      '${value.day} ${_months[value.month - 1]}, ${time(value)}';
}
