import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Remembers which in-flight rides were already reopened automatically, so
/// after an app restart the live ride screen comes back exactly once — and
/// a user who then leaves it on purpose is not pulled back in.
class RideResumeGate {
  final Set<String> _resumed = {};

  /// True the first time it is asked about [rideId].
  bool shouldResume(String rideId) => _resumed.add(rideId);
}

final rideResumeGateProvider = Provider<RideResumeGate>(
  (ref) => RideResumeGate(),
);
