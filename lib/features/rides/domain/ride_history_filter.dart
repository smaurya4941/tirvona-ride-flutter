import 'ride_formatters.dart';

/// The date presets on the ride history screen.
enum RideHistoryPeriod {
  all('All rides'),
  today('Today'),
  yesterday('Yesterday'),
  last7Days('Last 7 days'),
  last30Days('Last 30 days'),
  custom('Choose dates…');

  const RideHistoryPeriod(this.label);
  final String label;
}

/// A local-time window: [start] inclusive, [end] exclusive; null = open.
typedef RideHistoryWindow = ({DateTime? start, DateTime? end});

/// What the history list is filtered by. Custom days are whole local days
/// ([customFrom]..[customTo], both inclusive).
class RideHistoryFilter {
  const RideHistoryFilter(this.period) : customFrom = null, customTo = null;

  RideHistoryFilter.custom({required DateTime from, required DateTime to})
    : period = RideHistoryPeriod.custom,
      customFrom = _day(from),
      customTo = _day(to);

  static const all = RideHistoryFilter(RideHistoryPeriod.all);

  final RideHistoryPeriod period;
  final DateTime? customFrom;
  final DateTime? customTo;

  /// The window sent to `GET /rides`, computed from [now] each time so a
  /// list left open past midnight still means "today".
  RideHistoryWindow window(DateTime now) {
    final today = _day(now);
    DateTime daysAgo(int days) =>
        DateTime(today.year, today.month, today.day - days);
    return switch (period) {
      RideHistoryPeriod.all => (start: null, end: null),
      RideHistoryPeriod.today => (start: today, end: null),
      RideHistoryPeriod.yesterday => (start: daysAgo(1), end: today),
      // Today plus the six days before it.
      RideHistoryPeriod.last7Days => (start: daysAgo(6), end: null),
      RideHistoryPeriod.last30Days => (start: daysAgo(29), end: null),
      RideHistoryPeriod.custom => (
        start: customFrom,
        end: customTo == null
            ? null
            : DateTime(customTo!.year, customTo!.month, customTo!.day + 1),
      ),
    };
  }

  /// Shown in the picker: the preset name, or the chosen dates.
  String get label {
    if (period != RideHistoryPeriod.custom) return period.label;
    final from = customFrom!, to = customTo!;
    return from == to
        ? RideFormat.date(from)
        : '${RideFormat.date(from)} – ${RideFormat.date(to)}';
  }

  /// For the empty state: "No rides today", "No rides in the last 7 days"…
  String get emptyMessage => switch (period) {
    RideHistoryPeriod.all => 'No rides yet',
    RideHistoryPeriod.today => 'No rides today',
    RideHistoryPeriod.yesterday => 'No rides yesterday',
    RideHistoryPeriod.last7Days => 'No rides in the last 7 days',
    RideHistoryPeriod.last30Days => 'No rides in the last 30 days',
    RideHistoryPeriod.custom =>
      customFrom == customTo ? 'No rides on $label' : 'No rides from $label',
  };

  @override
  bool operator ==(Object other) =>
      other is RideHistoryFilter &&
      other.period == period &&
      other.customFrom == customFrom &&
      other.customTo == customTo;

  @override
  int get hashCode => Object.hash(period, customFrom, customTo);

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
