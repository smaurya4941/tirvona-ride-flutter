import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import 'realtime_models.dart';

/// The app's one realtime connection. Screens and controllers never touch a
/// socket; they consume [events] / [sessions] / [status] and call the few
/// operations below. Business actions stay on REST.
abstract interface class RealtimeClient {
  RealtimeStatus get status;
  Stream<RealtimeStatus> get statusChanges;

  /// Every ride event addressed to this user.
  Stream<RealtimeEvent> get events;

  /// User-level events that are not about one ride (`notification.*`).
  Stream<RealtimeNotice> get notices;

  /// Emits after every successful (re)connect — the signal to re-sync.
  Stream<RealtimeSession> get sessions;

  /// Idempotent. Connects with the stored access token.
  void connect();

  /// Idempotent. Closes the socket and stops reconnecting.
  void disconnect();

  /// Asks to be in `ride:{rideId}`; remembered and re-joined on reconnect.
  Future<RealtimeAck> joinRide(String rideId);

  Future<void> leaveRide(String rideId);

  /// One GPS fix from the driver app (see `driver.location` on the server).
  Future<RealtimeAck> sendDriverLocation(Map<String, dynamic> fix);
}

/// The event body of a server push, as handed over by `socket_io_client`.
///
/// The server enables Socket.IO connection-state recovery, which appends the
/// packet's recovery offset as an extra argument to every event it emits
/// (`[body, "Q3SJQ-S"]`). The Node client strips it; the Dart client passes
/// all arguments as a List. Without unwrapping, every push — offers, status
/// changes, live location, notifications — fails its `is Map` check and is
/// silently dropped. Acknowledgements are not affected.
@visibleForTesting
Object? eventBody(Object? data) =>
    data is List ? (data.isEmpty ? null : data.first) : data;

/// Socket.IO implementation.
///
/// * WebSocket transport only (matches the server).
/// * The access token is read on every (re)connect attempt, so a refreshed
///   token is picked up automatically.
/// * Server-side rejections (`AUTH_TOKEN_EXPIRED`, `session.expired`) are not
///   retried by Socket.IO itself: the client refreshes the token once through
///   [refreshAccessToken] and reconnects; if that fails it reports
///   [RealtimeStatus.unauthorized] and calls [onUnauthorized].
/// * Network loss is retried by Socket.IO with exponential backoff.
class SocketIoRealtimeClient implements RealtimeClient {
  SocketIoRealtimeClient({
    required this._url,
    required this._readAccessToken,
    required this._refreshAccessToken,
    required this._onUnauthorized,
    this._ackTimeout = const Duration(seconds: 8),
  });

  final String _url;
  final Future<String?> Function() _readAccessToken;

  /// Returns a new access token, or `null` when the session is gone.
  final Future<String?> Function() _refreshAccessToken;
  final void Function() _onUnauthorized;
  final Duration _ackTimeout;

  final _statusController = StreamController<RealtimeStatus>.broadcast();
  final _eventController = StreamController<RealtimeEvent>.broadcast();
  final _sessionController = StreamController<RealtimeSession>.broadcast();
  final _noticeController = StreamController<RealtimeNotice>.broadcast();
  final Set<String> _joinedRides = {};

  sio.Socket? _socket;
  RealtimeStatus _status = RealtimeStatus.idle;
  bool _wanted = false;
  bool _refreshing = false;

  @override
  RealtimeStatus get status => _status;

  @override
  Stream<RealtimeStatus> get statusChanges => _statusController.stream;

  @override
  Stream<RealtimeEvent> get events => _eventController.stream;

  @override
  Stream<RealtimeSession> get sessions => _sessionController.stream;

  @override
  Stream<RealtimeNotice> get notices => _noticeController.stream;

  @override
  void connect() {
    _wanted = true;
    final existing = _socket;
    if (existing != null) {
      if (!existing.connected) existing.connect();
      return;
    }
    _setStatus(RealtimeStatus.connecting);

    final socket = sio.io(
      _url,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(15000)
          .setAuthFn((callback) {
            unawaited(
              _readAccessToken().then(
                (token) => callback({'token': token ?? ''}),
                onError: (Object _) => callback({'token': ''}),
              ),
            );
          })
          .build(),
    );
    _socket = socket;

    socket
      ..onConnect((_) => _setStatus(RealtimeStatus.connected))
      ..onDisconnect(_handleDisconnect)
      ..onConnectError(_handleConnectError)
      ..onReconnectAttempt((_) => _setStatus(RealtimeStatus.reconnecting))
      ..on(RealtimeEvents.sessionReady, _handleSessionReady)
      ..on(RealtimeEvents.sessionExpired, (_) => _log('Session expired'))
      ..onAny((event, raw) {
        final data = eventBody(raw);
        if (event.startsWith('notification.')) {
          if (data is Map) {
            _noticeController.add(
              RealtimeNotice(event: event, data: data.cast<String, dynamic>()),
            );
          }
          return;
        }
        // Ride status events, and circuit progress (stops, usage, warnings).
        if (!event.startsWith('ride.') && !event.startsWith('circuit.')) return;
        final parsed = RealtimeEvent.tryParse(event, data);
        if (parsed != null) {
          _eventController.add(parsed);
        } else {
          _log('Ignored malformed $event push');
        }
      })
      ..connect();
  }

  @override
  void disconnect() {
    _wanted = false;
    _joinedRides.clear();
    final socket = _socket;
    _socket = null;
    socket
      ?..clearListeners()
      ..dispose();
    _setStatus(RealtimeStatus.idle);
  }

  @override
  Future<RealtimeAck> joinRide(String rideId) async {
    _joinedRides.add(rideId);
    final ack = await _emit(RealtimeEvents.joinRide, {'rideId': rideId});
    // A ride that is over or not ours is not worth re-joining.
    if (ack.code == 'RIDE_NOT_FOUND' || ack.code == 'RIDE_NOT_ACTIVE') {
      _joinedRides.remove(rideId);
    }
    return ack;
  }

  @override
  Future<void> leaveRide(String rideId) async {
    _joinedRides.remove(rideId);
    await _emit(RealtimeEvents.leaveRide, {'rideId': rideId});
  }

  @override
  Future<RealtimeAck> sendDriverLocation(Map<String, dynamic> fix) =>
      _emit(RealtimeEvents.driverLocation, fix);

  Future<RealtimeAck> _emit(String event, Map<String, dynamic> body) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      return const RealtimeAck.unavailable();
    }
    try {
      final payload = await socket
          .timeout(_ackTimeout.inMilliseconds)
          .emitWithAckAsync(event, body);
      return RealtimeAck.fromPayload(payload);
    } catch (_) {
      return const RealtimeAck.unavailable();
    }
  }

  void _handleSessionReady(dynamic raw) {
    final data = eventBody(raw);
    if (data is! Map) {
      _log('Ignored malformed session.ready');
      return;
    }
    final session = RealtimeSession.fromJson(data.cast<String, dynamic>());
    _setStatus(RealtimeStatus.connected);
    // Rooms the app asked for that the server did not restore by itself.
    for (final rideId in _joinedRides.toList()) {
      if (!session.rideIds.contains(rideId)) unawaited(joinRide(rideId));
    }
    _sessionController.add(session);
  }

  void _handleDisconnect(dynamic reason) {
    if (!_wanted) return;
    _log('Disconnected: $reason');
    // A server-initiated disconnect (token expired, account blocked) is not
    // retried by Socket.IO; transport loss is.
    if (reason == 'io server disconnect') {
      unawaited(_refreshAndReconnect());
    } else {
      _setStatus(RealtimeStatus.reconnecting);
    }
  }

  void _handleConnectError(dynamic error) {
    if (!_wanted) return;
    final code = error is Map ? error['message'] as String? : null;
    if (code == null) {
      // Transport error: Socket.IO's backoff keeps retrying.
      _setStatus(RealtimeStatus.reconnecting);
      return;
    }
    _log('Connection refused: $code');
    if (code == 'AUTH_TOKEN_EXPIRED' || code == 'AUTH_UNAUTHORIZED') {
      unawaited(_refreshAndReconnect());
    } else {
      _giveUp();
    }
  }

  Future<void> _refreshAndReconnect() async {
    if (_refreshing) return;
    _refreshing = true;
    _setStatus(RealtimeStatus.reconnecting);
    try {
      final token = await _refreshAccessToken();
      if (!_wanted) return;
      if (token == null) return _giveUp();
      _socket?.connect();
    } catch (_) {
      // Network trouble while refreshing: try again shortly.
      if (_wanted) {
        Timer(const Duration(seconds: 5), () {
          if (_wanted && !(_socket?.connected ?? false)) {
            unawaited(_refreshAndReconnect());
          }
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  void _giveUp() {
    _setStatus(RealtimeStatus.unauthorized);
    _onUnauthorized();
  }

  void _setStatus(RealtimeStatus next) {
    if (_status == next) return;
    _status = next;
    _statusController.add(next);
  }

  void _log(String message) => developer.log(message, name: 'realtime');
}
