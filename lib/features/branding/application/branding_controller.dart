import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/branding_cache.dart';
import '../data/branding_repository.dart';
import '../domain/branding.dart';

/// The cache opened in `bootstrap()` before the first frame, with what it
/// held. Tests override both; `null` cache = nothing is persisted.
final brandingCacheProvider = Provider<BrandingCache?>((ref) => null);
final initialBrandingProvider = Provider<BrandingState>(
  (ref) => BrandingState.defaults,
);

/// How often a resumed app re-checks for new branding.
const kBrandingRefreshInterval = Duration(minutes: 15);

/// Logo and splash the app shows. Starts from the on-device cache (so there
/// is no flash of the default), then syncs with `GET /branding` at launch
/// (see [brandingSyncProvider]) and when the app returns to the foreground.
/// Failures keep what is cached — branding must never block or break the app.
class BrandingController extends Notifier<BrandingState> {
  Future<void>? _inFlight;
  DateTime? _lastSync;
  AppLifecycleListener? _lifecycle;

  @override
  BrandingState build() {
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.onDispose(() => _lifecycle?.dispose());
    return ref.watch(initialBrandingProvider);
  }

  void _onResume() {
    final last = _lastSync;
    if (last == null ||
        DateTime.now().difference(last) >= kBrandingRefreshInterval) {
      unawaited(refresh());
    }
  }

  /// Syncs with the server. Concurrent calls share one run.
  Future<void> refresh() =>
      _inFlight ??= _sync().whenComplete(() => _inFlight = null);

  Future<void> _sync() async {
    try {
      final repository = ref.read(brandingRepositoryProvider);
      final cache = ref.read(brandingCacheProvider);
      final remote = await repository.fetch();
      var next = state;
      for (final kind in BrandAssetKind.values) {
        final asset = remote[kind];
        if (asset == null) {
          next = next.withImage(kind, null);
          continue;
        }
        if (next[kind]?.version == asset.version) continue;
        try {
          final bytes = await repository.download(asset);
          final image = cache == null ? null : await cache.store(asset, bytes);
          // Without a cache there is nowhere to keep the file; stay on the
          // default rather than show a stale image.
          next = next.withImage(kind, image);
        } on Object catch (error) {
          developer.log(
            'Could not download the ${kind.name}',
            error: error,
            name: 'branding',
          );
        }
      }
      _lastSync = DateTime.now();
      if (next != state) {
        await cache?.commit(next);
        if (ref.mounted) state = next;
      }
    } on Object catch (error) {
      developer.log('Branding sync failed', error: error, name: 'branding');
    }
  }
}

final brandingControllerProvider =
    NotifierProvider<BrandingController, BrandingState>(BrandingController.new);

/// Watched by the app shell: one sync per launch. Screens that only show the
/// logo read [brandingControllerProvider] and never hit the network.
final brandingSyncProvider = Provider<void>((ref) {
  final controller = ref.watch(brandingControllerProvider.notifier);
  Future.microtask(controller.refresh);
});
