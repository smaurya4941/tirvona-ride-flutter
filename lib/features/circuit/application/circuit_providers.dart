import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../data/circuit_repository.dart';
import '../domain/circuit_models.dart';

/// Bookable circuit packages (only ACTIVE ones reach the app).
final circuitPackagesProvider =
    FutureProvider.autoDispose<List<CircuitPackage>>(
      (ref) => ref.watch(circuitRepositoryProvider).packages(),
    );

final circuitPackageProvider = FutureProvider.autoDispose
    .family<CircuitPackage, String>(
      (ref, id) => ref.watch(circuitRepositoryProvider).package(id),
    );

/// Absolute URL of a package's cover image, or null when it has none.
final circuitCoverUrlProvider = Provider.family<String?, String?>((
  ref,
  coverPath,
) {
  if (coverPath == null || coverPath.isEmpty) return null;
  return '${ref.watch(appConfigProvider).apiBaseUrl}$coverPath';
});

/// Circuit moments worth a snackbar (arrived at a stop, next stop, time and
/// distance warnings) for one ride. The ride view itself refreshes through
/// rideProvider, which applies every pushed snapshot.
final circuitNoticesProvider = StreamProvider.autoDispose
    .family<CircuitNotice, ({String rideId, bool asDriver})>(
      (ref, key) => ref
          .watch(realtimeClientProvider)
          .events
          .where(
            (event) =>
                event.rideId == key.rideId &&
                event.event.startsWith('circuit.'),
          )
          .map(
            (event) => CircuitNotice.fromEvent(
              event.event,
              event.data,
              asDriver: key.asDriver,
            ),
          )
          .where((notice) => notice != null)
          .cast<CircuitNotice>(),
    );
