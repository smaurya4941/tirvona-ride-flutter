import 'package:flutter/foundation.dart';

/// Connection state of the realtime socket, for UI ("Reconnecting…") and
/// for services that must know whether a send can go out now.
enum RealtimeStatus {
  /// Not signed in (or signed out) — nothing to connect.
  idle,
  connecting,
  connected,

  /// Lost the connection; retrying with backoff.
  reconnecting,

  /// The server refused the session and it could not be refreshed.
  unauthorized,
}

/// Server event names — mirrors `realtime.constants.ts` on the backend.
abstract final class RealtimeEvents {
  static const requested = 'ride.requested';
  static const driverAssigned = 'ride.driver_assigned';
  static const searching = 'ride.searching';
  static const offerWithdrawn = 'ride.offer_withdrawn';
  static const driverAccepted = 'ride.driver_accepted';
  static const driverArriving = 'ride.driver_arriving';
  static const driverArrived = 'ride.driver_arrived';
  static const otpRefreshed = 'ride.otp_refreshed';

  /// The driver asked to end the trip / took the request back.
  static const endRequested = 'ride.end_requested';
  static const endCancelled = 'ride.end_cancelled';
  static const started = 'ride.started';
  static const locationUpdated = 'ride.location_updated';
  static const completed = 'ride.completed';
  static const cancelled = 'ride.cancelled';
  static const noDriverAvailable = 'ride.no_driver_available';

  /// The ride's payment status changed (Phase 4).
  static const paymentUpdated = 'ride.payment_updated';

  /// A new in-app notification (Phase 5): `{ notification, unreadCount }`.
  static const notificationCreated = 'notification.created';

  /// Read state changed on another device: `{ unreadCount }`.
  static const notificationUnreadCount = 'notification.unread_count';

  static const sessionReady = 'session.ready';
  static const sessionExpired = 'session.expired';

  static const joinRide = 'ride.join';
  static const leaveRide = 'ride.leave';
  static const driverLocation = 'driver.location';
}

/// A non-ride, user-level event (currently `notification.*`).
@immutable
class RealtimeNotice {
  const RealtimeNotice({required this.event, required this.data});

  final String event;
  final Map<String, dynamic> data;
}

/// One ride event: `{ event, rideId, status, stateVersion, timestamp, data, ride? }`.
///
/// [ride] is the recipient's own view (same JSON as `GET /rides/:id`) on
/// status events and absent on high-frequency ones.
@immutable
class RealtimeEvent {
  const RealtimeEvent({
    required this.event,
    required this.rideId,
    required this.timestamp,
    required this.data,
    this.status,
    this.stateVersion,
    this.ride,
  });

  static RealtimeEvent? tryParse(String event, Object? payload) {
    if (payload is! Map) return null;
    final json = payload.cast<String, dynamic>();
    final rideId = json['rideId'];
    if (rideId is! String) return null;
    final data = json['data'];
    final ride = json['ride'];
    return RealtimeEvent(
      event: event,
      rideId: rideId,
      status: json['status'] as String?,
      stateVersion: (json['stateVersion'] as num?)?.toInt(),
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      data: data is Map ? data.cast<String, dynamic>() : const {},
      ride: ride is Map ? ride.cast<String, dynamic>() : null,
    );
  }

  final String event;
  final String rideId;
  final String? status;
  final int? stateVersion;
  final DateTime timestamp;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? ride;
}

/// Sent by the server after every (re)connect. Consumers treat it as "re-sync
/// from REST now": anything may have happened while the socket was down.
@immutable
class RealtimeSession {
  const RealtimeSession({
    required this.userId,
    required this.role,
    required this.rideIds,
    required this.recovered,
  });

  factory RealtimeSession.fromJson(Map<String, dynamic> json) =>
      RealtimeSession(
        userId: json['userId'] as String? ?? '',
        role: json['role'] as String? ?? '',
        rideIds: (json['rideIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        recovered: json['recovered'] as bool? ?? false,
      );

  final String userId;
  final String role;

  /// Ride rooms the server already put this socket back into.
  final List<String> rideIds;

  /// Socket.IO connection-state recovery restored missed events too.
  final bool recovered;
}

/// A Socket.IO acknowledgement: `{ ok: true, ... }` or `{ ok: false, code, message }`.
@immutable
class RealtimeAck {
  const RealtimeAck({required this.ok, this.code, this.message, this.body});

  factory RealtimeAck.fromPayload(Object? payload) {
    if (payload is! Map) {
      return const RealtimeAck(ok: false, code: 'INVALID_ACK');
    }
    final json = payload.cast<String, dynamic>();
    return RealtimeAck(
      ok: json['ok'] == true,
      code: json['code'] as String?,
      message: json['message'] as String?,
      body: json,
    );
  }

  /// No connection, or the server did not answer in time.
  const RealtimeAck.unavailable()
    : this(ok: false, code: 'NOT_CONNECTED', message: 'Not connected');

  final bool ok;
  final String? code;
  final String? message;
  final Map<String, dynamic>? body;
}
