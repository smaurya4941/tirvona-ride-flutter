import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/features/rides/data/ride_repository.dart';
import 'package:tirvona_ride/features/rides/domain/ride_history_filter.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';
import 'package:tirvona_ride/features/rides/presentation/ride_history_tab.dart';

import 'ride_models_test.dart' show rideJson;

Ride _ride(int n) => Ride.fromJson(
  rideJson(
    status: 'COMPLETED',
    extra: {
      'id': 'ride${n.toString().padLeft(4, '0')}',
      'rideCode': 'TRCODE$n',
    },
  ),
);

class _Call {
  _Call(this.page, this.limit, this.startDate, this.endDate);
  final int page;
  final int limit;
  final DateTime? startDate;
  final DateTime? endDate;
}

/// Serves [total] rides in pages; [gate] (when set) holds every response.
class _HistoryRides extends RideRepository {
  _HistoryRides(this.total, {this.filteredTotal}) : super(Dio());

  final int total;

  /// Served instead of [total] when a date window is sent.
  final int? filteredTotal;
  final calls = <_Call>[];
  Completer<void>? gate;

  @override
  Future<RidePage> history({
    int page = 1,
    int limit = 20,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    calls.add(_Call(page, limit, startDate, endDate));
    await gate?.future;
    final total = startDate == null && endDate == null
        ? this.total
        : filteredTotal ?? this.total;
    final first = (page - 1) * limit;
    final items = [
      for (var i = first; i < total && i < first + limit; i++) _ride(i),
    ];
    return RidePage(
      items: items,
      page: page,
      total: total,
      hasMore: page * limit < total,
    );
  }
}

Future<void> _pump(WidgetTester tester, _HistoryRides rides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [rideRepositoryProvider.overrideWithValue(rides)],
      child: MaterialApp(
        home: Scaffold(body: RideHistoryTab(rideRoute: (id) => '/r/$id')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('ride-history-filter')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('RideHistoryFilter.window', () {
    final now = DateTime(2026, 10, 1, 13, 13);

    test('all rides is unbounded', () {
      final w = RideHistoryFilter.all.window(now);
      expect(w.start, isNull);
      expect(w.end, isNull);
    });

    test('today starts at local midnight', () {
      final w = const RideHistoryFilter(RideHistoryPeriod.today).window(now);
      expect(w.start, DateTime(2026, 10, 1));
      expect(w.end, isNull);
    });

    test('yesterday is one whole day, across a month boundary', () {
      final w = const RideHistoryFilter(
        RideHistoryPeriod.yesterday,
      ).window(now);
      expect(w.start, DateTime(2026, 9, 30));
      expect(w.end, DateTime(2026, 10, 1));
    });

    test('last 7 / 30 days include today', () {
      expect(
        const RideHistoryFilter(RideHistoryPeriod.last7Days).window(now).start,
        DateTime(2026, 9, 25),
      );
      expect(
        const RideHistoryFilter(RideHistoryPeriod.last30Days).window(now).start,
        DateTime(2026, 9, 2),
      );
    });

    test('custom dates cover whole days, end exclusive', () {
      final filter = RideHistoryFilter.custom(
        from: DateTime(2026, 9, 20, 15),
        to: DateTime(2026, 9, 22, 8),
      );
      final w = filter.window(now);
      expect(w.start, DateTime(2026, 9, 20));
      expect(w.end, DateTime(2026, 9, 23));
      expect(filter.label, '20 Sep 2026 – 22 Sep 2026');
      expect(
        RideHistoryFilter.custom(
          from: DateTime(2026, 9, 20),
          to: DateTime(2026, 9, 20),
        ).label,
        '20 Sep 2026',
      );
    });
  });

  group('RideHistoryTab', () {
    testWidgets('loads all rides by default and pages on scroll', (
      tester,
    ) async {
      final rides = _HistoryRides(25);
      await _pump(tester, rides);

      expect(rides.calls.single.page, 1);
      expect(rides.calls.single.startDate, isNull);
      expect(rides.calls.single.endDate, isNull);
      expect(find.text('Showing 10 of 25 rides'), findsOneWidget);

      // Scroll to the end until everything is loaded.
      for (var i = 0; i < 10 && rides.calls.length < 3; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -2000));
        await tester.pumpAndSettle();
      }
      expect(rides.calls.map((c) => c.page), [1, 2, 3]);
      expect(find.text('25 rides'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(find.text("That's all your rides for this period"), findsOneWidget);
      expect(rides.calls, hasLength(3));
    });

    testWidgets('changing the filter restarts from page 1 with the window', (
      tester,
    ) async {
      final rides = _HistoryRides(3);
      await _pump(tester, rides);

      await _choose(tester, 'Yesterday');
      final call = rides.calls.last;
      expect(call.page, 1);
      final today = DateTime.now();
      final midnight = DateTime(today.year, today.month, today.day);
      expect(call.endDate, midnight);
      expect(
        call.startDate,
        DateTime(midnight.year, midnight.month, midnight.day - 1),
      );
      expect(find.text('Yesterday'), findsWidgets);
    });

    testWidgets('a page for the old filter is dropped after a change', (
      tester,
    ) async {
      final rides = _HistoryRides(6, filteredTotal: 3)
        ..gate = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [rideRepositoryProvider.overrideWithValue(rides)],
          child: MaterialApp(
            home: Scaffold(body: RideHistoryTab(rideRoute: (id) => '/r/$id')),
          ),
        ),
      );
      await tester.pump();
      // First request ("All rides") still in flight; switch to Today.
      await tester.tap(find.byKey(const ValueKey('ride-history-filter')));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Today').last);
      await tester.pump(const Duration(seconds: 1));
      expect(rides.calls, hasLength(2));
      expect(rides.calls.last.startDate, isNotNull);

      rides.gate!.complete();
      await tester.pumpAndSettle();
      // Only the Today page was applied: 3 rides, not 6.
      expect(find.text('3 rides'), findsOneWidget);
      expect(find.text('TRCODE0'), findsOneWidget);
    });

    testWidgets('empty period offers to show all rides', (tester) async {
      final rides = _HistoryRides(0);
      await _pump(tester, rides);
      expect(find.text('No rides yet'), findsOneWidget);

      await _choose(tester, 'Today');
      expect(find.text('No rides today'), findsOneWidget);
      await tester.tap(find.text('Show all rides'));
      await tester.pumpAndSettle();
      expect(rides.calls.last.startDate, isNull);
      expect(find.text('No rides yet'), findsOneWidget);
    });

    testWidgets('cancelling the date picker keeps the current filter', (
      tester,
    ) async {
      final rides = _HistoryRides(2);
      await _pump(tester, rides);
      await _choose(tester, 'Choose dates…');
      expect(find.text('Show rides between'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(rides.calls, hasLength(1));
      expect(find.text('All rides'), findsOneWidget);
    });
  });
}
