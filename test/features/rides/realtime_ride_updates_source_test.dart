import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/core/network/api_exception.dart';
import 'package:tirvona_ride/core/realtime/realtime_client.dart';
import 'package:tirvona_ride/core/realtime/realtime_models.dart';
import 'package:tirvona_ride/features/rides/application/ride_updates_source.dart';
import 'package:tirvona_ride/features/rides/data/ride_repository.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

import 'ride_models_test.dart' show rideJson;

const _rideId = '66f0c0ffee0000000000abcd';

Map<String, dynamic> _ride(
  String status,
  int version, [
  Map<String, dynamic>? extra,
]) => rideJson(status: status, extra: {'stateVersion': version, ...?extra});

/// Scripted REST: each `getRide` returns the next queued snapshot.
class _FakeRepository extends RideRepository {
  _FakeRepository() : super(Dio());

  final List<Object> rideSnapshots = [];
  List<Ride> requests = [];
  int rideCalls = 0;
  int requestCalls = 0;

  @override
  Future<Ride> getRide(String id) async {
    rideCalls++;
    final next = rideSnapshots.removeAt(0);
    if (next is Exception) throw next;
    return Ride.fromJson(next as Map<String, dynamic>);
  }

  @override
  Future<List<Ride>> driverRequests() async {
    requestCalls++;
    return requests;
  }
}

/// An in-memory socket: tests push events and sessions by hand.
class _FakeRealtime implements RealtimeClient {
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _sessions = StreamController<RealtimeSession>.broadcast();
  final _statuses = StreamController<RealtimeStatus>.broadcast();
  final joined = <String>[];
  RealtimeStatus _status = RealtimeStatus.connected;

  set status(RealtimeStatus next) {
    _status = next;
    _statuses.add(next);
  }

  void push(
    String event, {
    Map<String, dynamic>? ride,
    Map<String, dynamic> data = const {},
  }) {
    _events.add(
      RealtimeEvent(
        event: event,
        rideId: _rideId,
        timestamp: DateTime.now(),
        data: data,
        ride: ride,
        stateVersion: ride?['stateVersion'] as int?,
      ),
    );
  }

  void reconnect() => _sessions.add(
    const RealtimeSession(
      userId: 'u',
      role: 'CUSTOMER',
      rideIds: [],
      recovered: false,
    ),
  );

  @override
  RealtimeStatus get status => _status;
  @override
  Stream<RealtimeStatus> get statusChanges => _statuses.stream;
  @override
  Stream<RealtimeEvent> get events => _events.stream;
  @override
  Stream<RealtimeSession> get sessions => _sessions.stream;
  @override
  Stream<RealtimeNotice> get notices => const Stream.empty();
  @override
  void connect() {}
  @override
  void disconnect() {}
  @override
  Future<RealtimeAck> joinRide(String rideId) async {
    joined.add(rideId);
    return const RealtimeAck(ok: true);
  }

  @override
  Future<void> leaveRide(String rideId) async {}
  @override
  Future<RealtimeAck> sendDriverLocation(Map<String, dynamic> fix) async =>
      const RealtimeAck(ok: true);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepository repository;
  late _FakeRealtime realtime;
  late RealtimeRideUpdatesSource source;

  setUp(() {
    repository = _FakeRepository();
    realtime = _FakeRealtime();
    source = RealtimeRideUpdatesSource(repository, realtime);
  });

  test(
    'joins the ride room, then applies pushed snapshots without polling',
    () async {
      repository.rideSnapshots.add(_ride('SEARCHING', 1));
      final statuses = <RideStatus>[];
      final done = Completer<void>();
      source
          .watchRide(_rideId)
          .listen((ride) => statuses.add(ride.status), onDone: done.complete);
      await _settle();

      expect(realtime.joined, [_rideId]);
      realtime
        ..push(RealtimeEvents.driverAssigned, ride: _ride('DRIVER_ASSIGNED', 2))
        ..push(RealtimeEvents.driverAccepted, ride: _ride('DRIVER_ACCEPTED', 3))
        ..push(RealtimeEvents.completed, ride: _ride('COMPLETED', 7));
      await done.future;

      expect(statuses, [
        RideStatus.searching,
        RideStatus.driverAssigned,
        RideStatus.driverAccepted,
        RideStatus.completed,
      ]);
      expect(
        repository.rideCalls,
        1,
        reason: 'status changes must arrive by push, not GET',
      );
    },
  );

  test('drops a snapshot older than the one already shown', () async {
    repository.rideSnapshots.add(_ride('DRIVER_ACCEPTED', 3));
    final statuses = <RideStatus>[];
    final subscription = source
        .watchRide(_rideId)
        .listen((ride) => statuses.add(ride.status));
    await _settle();

    realtime
      ..push(RealtimeEvents.driverArrived, ride: _ride('DRIVER_ARRIVED', 4))
      // A late, older push (e.g. delivered after a recovery replay).
      ..push(RealtimeEvents.driverAccepted, ride: _ride('DRIVER_ACCEPTED', 3));
    await _settle();

    expect(statuses, [RideStatus.driverAccepted, RideStatus.driverArrived]);
    await subscription.cancel();
  });

  test(
    're-syncs from REST after a reconnect so missed events are recovered',
    () async {
      repository.rideSnapshots
        ..add(_ride('DRIVER_ACCEPTED', 3))
        // While offline the driver arrived; the event never reached us.
        ..add(
          _ride('DRIVER_ARRIVED', 4, {
            'otp': {'code': '4821'},
          }),
        );
      final rides = <Ride>[];
      final subscription = source.watchRide(_rideId).listen(rides.add);
      await _settle();

      realtime.reconnect();
      await _settle();

      expect(rides.map((ride) => ride.status), [
        RideStatus.driverAccepted,
        RideStatus.driverArrived,
      ]);
      expect(rides.last.otp?.code, '4821');
      await subscription.cancel();
    },
  );

  test('a 404 is final: the stream errors once and closes', () async {
    repository.rideSnapshots.add(
      const ApiException(
        kind: ApiErrorKind.client,
        message: 'Ride not found',
        statusCode: 404,
      ),
    );
    final errors = <Object>[];
    final done = Completer<void>();
    source
        .watchRide(_rideId)
        .listen((_) {}, onError: errors.add, onDone: done.complete);
    await done.future;
    expect(errors, hasLength(1));
  });

  test('driver offers appear and disappear from pushed events', () async {
    final lists = <List<String>>[];
    final subscription = source.watchDriverRequests().listen(
      (rides) => lists.add(rides.map((ride) => ride.id).toList()),
    );
    await _settle();

    realtime.push(RealtimeEvents.requested, ride: _ride('DRIVER_ASSIGNED', 2));
    await _settle();
    realtime.push(
      RealtimeEvents.offerWithdrawn,
      data: {'reason': 'ASSIGNMENT_TIMEOUT'},
    );
    await _settle();

    expect(lists, [
      <String>[],
      [_rideId],
      <String>[],
    ]);
    await subscription.cancel();
  });

  test('parses live driver positions for the ride', () async {
    final positions = <DriverPosition>[];
    final subscription = source
        .watchDriverPosition(_rideId)
        .listen(positions.add);
    realtime.push(
      RealtimeEvents.locationUpdated,
      data: {
        'latitude': 27.57,
        'longitude': 77.67,
        'heading': 90,
        'recordedAt': '2026-09-24T10:00:00Z',
      },
    );
    await _settle();
    expect(positions.single.heading, 90);
    expect(positions.single.latitude, 27.57);
    await subscription.cancel();
  });

  test('unwraps the recovery offset Socket.IO appends to pushed events', () {
    final body = {'rideId': _rideId};
    expect(eventBody([body, 'Q3SJQ-S']), same(body));
    expect(eventBody(body), same(body));
    expect(eventBody(const <Object>[]), isNull);
    expect(eventBody(null), isNull);
  });

  group('REST safety net', () {
    setUp(() {
      source = RealtimeRideUpdatesSource(
        repository,
        realtime,
        pollWhileDisconnected: const Duration(milliseconds: 20),
        offerPollWhileConnected: const Duration(milliseconds: 400),
        ridePollWhileConnected: const Duration(milliseconds: 400),
      );
    });

    test('shows a new offer from REST while the socket is down', () async {
      realtime.status = RealtimeStatus.reconnecting;
      final lists = <List<String>>[];
      final subscription = source.watchDriverRequests().listen(
        (rides) => lists.add(rides.map((ride) => ride.id).toList()),
      );
      await _settle();
      expect(lists.last, isEmpty);

      // Offered while disconnected: no push will ever arrive for it.
      repository.requests = [Ride.fromJson(_ride('DRIVER_ASSIGNED', 2))];
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(lists.last, [_rideId]);
      await subscription.cancel();
    });

    test(
      'polls rarely while connected and never once the session is gone',
      () async {
        final subscription = source.watchDriverRequests().listen((_) {});
        await _settle();
        final afterListen = repository.requestCalls;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          repository.requestCalls,
          afterListen,
          reason: 'connected: slow poll',
        );

        realtime.status = RealtimeStatus.reconnecting;
        await Future<void>.delayed(const Duration(milliseconds: 70));
        expect(repository.requestCalls, greaterThanOrEqualTo(afterListen + 2));

        realtime.status = RealtimeStatus.unauthorized;
        final stopped = repository.requestCalls;
        await Future<void>.delayed(const Duration(milliseconds: 70));
        expect(repository.requestCalls, stopped);
        await subscription.cancel();
      },
    );

    test('re-fetches the ride while the socket is down', () async {
      realtime.status = RealtimeStatus.reconnecting;
      repository.rideSnapshots.addAll([
        _ride('DRIVER_ASSIGNED', 2),
        _ride('DRIVER_ACCEPTED', 3),
        for (var i = 0; i < 20; i++) _ride('DRIVER_ACCEPTED', 3),
      ]);
      final statuses = <RideStatus>[];
      final subscription = source
          .watchRide(_rideId)
          .listen((ride) => statuses.add(ride.status));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        statuses,
        containsAllInOrder([
          RideStatus.driverAssigned,
          RideStatus.driverAccepted,
        ]),
      );
      await subscription.cancel();
    });

    test('a malformed offer push is recovered from REST', () async {
      final subscription = source.watchDriverRequests().listen((_) {});
      await _settle();
      final before = repository.requestCalls;
      realtime.push(RealtimeEvents.requested, ride: {'id': _rideId});
      await _settle();
      expect(repository.requestCalls, before + 1);
      await subscription.cancel();
    });
  });
}
