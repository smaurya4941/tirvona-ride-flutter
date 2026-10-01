import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/branding.dart';

/// Admin-set logo/splash images kept on the phone, so the splash can show
/// the current artwork from the very first frame — before any network call —
/// and the app keeps its branding offline.
///
/// Layout: `<dir>/manifest.json` + one file per image version.
class BrandingCache {
  BrandingCache(this.directory);

  static Future<BrandingCache> inAppSupport() async => BrandingCache(
    Directory('${(await getApplicationSupportDirectory()).path}/branding'),
  );

  final Directory directory;

  File get _manifest => File('${directory.path}/manifest.json');

  /// What was cached last time. Entries whose file has gone missing are
  /// dropped, so callers can always trust the paths they get back.
  Future<BrandingState> load() async {
    try {
      if (!await _manifest.exists()) return BrandingState.defaults;
      final json = jsonDecode(await _manifest.readAsString());
      if (json is! Map<String, dynamic>) return BrandingState.defaults;
      var state = BrandingState.fromJson(json);
      for (final kind in BrandAssetKind.values) {
        final image = state[kind];
        if (image != null && !await File(image.filePath).exists()) {
          state = state.withImage(kind, null);
        }
      }
      return state;
    } on Object catch (error) {
      developer.log(
        'Branding cache unreadable',
        error: error,
        name: 'branding',
      );
      return BrandingState.defaults;
    }
  }

  /// Writes a downloaded image; the manifest is updated by [commit].
  Future<CachedBrandImage> store(
    RemoteBrandAsset asset,
    List<int> bytes,
  ) async {
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/${asset.kind.name}-${asset.version}.${asset.fileExtension}',
    );
    // Write-then-rename: a crash never leaves a half-written image behind
    // a manifest entry.
    final partial = File('${file.path}.part');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
    return CachedBrandImage(version: asset.version, filePath: file.path);
  }

  /// Saves the manifest and deletes image files it no longer references.
  Future<void> commit(BrandingState state) async {
    await directory.create(recursive: true);
    final partial = File('${_manifest.path}.part');
    await partial.writeAsString(jsonEncode(state.toJson()), flush: true);
    await partial.rename(_manifest.path);

    // Compared by name: listed paths use the platform's separator.
    final keep = {
      'manifest.json',
      for (final kind in BrandAssetKind.values)
        if (state[kind] case final image?) _fileName(image.filePath),
    };
    await for (final entity in directory.list()) {
      if (entity is File && !keep.contains(_fileName(entity.path))) {
        await entity.delete().catchError((_) => entity);
      }
    }
  }

  static String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;
}
