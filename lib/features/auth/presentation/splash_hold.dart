import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shortest time the brand splash stays up on a cold start. A signed-out
/// launch resolves the session in a few milliseconds, which would otherwise
/// flash the artwork for a single frame.
const kSplashMinDuration = Duration(milliseconds: 1600);

/// Overridable so tests can shorten or disable the hold.
final splashMinDurationProvider = Provider<Duration>(
  (ref) => kSplashMinDuration,
);

/// `true` until [splashMinDurationProvider] has elapsed since the app
/// started. The router keeps the splash route while this is `true`; it never
/// holds any other route, so deep links and push taps are not delayed.
class SplashHold extends Notifier<bool> {
  @override
  bool build() {
    final duration = ref.watch(splashMinDurationProvider);
    if (duration <= Duration.zero) return false;
    final timer = Timer(duration, () => state = false);
    ref.onDispose(timer.cancel);
    return true;
  }
}

final splashHoldProvider = NotifierProvider<SplashHold, bool>(SplashHold.new);
