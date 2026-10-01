import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/core/network/api_exception.dart';
import 'package:tirvona_ride/features/auth/presentation/splash_screen.dart';
import 'package:tirvona_ride/features/branding/application/branding_controller.dart';
import 'package:tirvona_ride/features/branding/data/branding_cache.dart';
import 'package:tirvona_ride/features/branding/data/branding_repository.dart';
import 'package:tirvona_ride/features/branding/domain/branding.dart';
import 'package:tirvona_ride/features/branding/presentation/brand_logo.dart';

RemoteBrandAsset _asset(BrandAssetKind kind, String version) =>
    RemoteBrandAsset(
      kind: kind,
      path: '/branding/assets/${kind.name}?v=$version',
      version: version,
      contentType: 'image/png',
    );

class _FakeRepository implements BrandingRepository {
  RemoteBranding remote = const RemoteBranding();
  Object? fetchError;
  final failDownloads = <BrandAssetKind>{};
  final downloads = <String>[];

  @override
  Future<RemoteBranding> fetch() async {
    if (fetchError case final error?) throw error;
    return remote;
  }

  @override
  Future<List<int>> download(RemoteBrandAsset asset) async {
    downloads.add('${asset.kind.name}@${asset.version}');
    if (failDownloads.contains(asset.kind)) {
      throw const ApiException(kind: ApiErrorKind.network, message: 'offline');
    }
    return [1, 2, 3, asset.version.length];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late BrandingCache cache;
  late _FakeRepository repository;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('branding_test');
    cache = BrandingCache(Directory('${dir.path}/branding'));
    repository = _FakeRepository();
  });

  tearDown(() => dir.delete(recursive: true));

  ProviderContainer container({
    BrandingState initial = BrandingState.defaults,
  }) {
    final container = ProviderContainer(
      overrides: [
        brandingRepositoryProvider.overrideWithValue(repository),
        brandingCacheProvider.overrideWithValue(cache),
        initialBrandingProvider.overrideWithValue(initial),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('BrandingCache', () {
    test('starts empty and round-trips what was committed', () async {
      expect(await cache.load(), BrandingState.defaults);

      final logo = await cache.store(_asset(BrandAssetKind.logo, 'v1'), [9]);
      await cache.commit(BrandingState(logo: logo));

      final reopened = BrandingCache(cache.directory);
      final loaded = await reopened.load();
      expect(loaded.logo, logo);
      expect(loaded.splash, isNull);
      expect(await File(logo.filePath).readAsBytes(), [9]);
    });

    test('forgets entries whose file disappeared', () async {
      final logo = await cache.store(_asset(BrandAssetKind.logo, 'v1'), [9]);
      await cache.commit(BrandingState(logo: logo));
      await File(logo.filePath).delete();
      expect((await cache.load()).logo, isNull);
    });

    test('deletes superseded image files on commit', () async {
      final v1 = await cache.store(_asset(BrandAssetKind.logo, 'v1'), [1]);
      await cache.commit(BrandingState(logo: v1));
      final v2 = await cache.store(_asset(BrandAssetKind.logo, 'v2'), [2]);
      await cache.commit(BrandingState(logo: v2));

      expect(File(v1.filePath).existsSync(), isFalse);
      expect(File(v2.filePath).existsSync(), isTrue);
    });

    test('treats a corrupt manifest as no branding', () async {
      await cache.directory.create(recursive: true);
      await File('${cache.directory.path}/manifest.json').writeAsString('{');
      expect(await cache.load(), BrandingState.defaults);
    });
  });

  group('BrandingController', () {
    test('downloads new images and persists them', () async {
      repository.remote = RemoteBranding(
        logo: _asset(BrandAssetKind.logo, 'l1'),
        splash: _asset(BrandAssetKind.splash, 's1'),
      );
      final c = container();
      await c.read(brandingControllerProvider.notifier).refresh();

      final state = c.read(brandingControllerProvider);
      expect(state.logo?.version, 'l1');
      expect(state.splash?.version, 's1');
      expect((await cache.load()), state);
    });

    test('skips versions it already has', () async {
      final logo = await cache.store(_asset(BrandAssetKind.logo, 'l1'), [1]);
      repository.remote = RemoteBranding(
        logo: _asset(BrandAssetKind.logo, 'l1'),
      );
      final c = container(initial: BrandingState(logo: logo));
      await c.read(brandingControllerProvider.notifier).refresh();

      expect(repository.downloads, isEmpty);
      expect(c.read(brandingControllerProvider).logo, logo);
    });

    test('goes back to the default when the admin resets', () async {
      final logo = await cache.store(_asset(BrandAssetKind.logo, 'l1'), [1]);
      await cache.commit(BrandingState(logo: logo));
      repository.remote = const RemoteBranding();
      final c = container(initial: BrandingState(logo: logo));
      await c.read(brandingControllerProvider.notifier).refresh();

      expect(c.read(brandingControllerProvider), BrandingState.defaults);
      expect(await cache.load(), BrandingState.defaults);
      expect(File(logo.filePath).existsSync(), isFalse);
    });

    test('keeps what it has when offline or a download fails', () async {
      final logo = await cache.store(_asset(BrandAssetKind.logo, 'l1'), [1]);
      final c = container(initial: BrandingState(logo: logo));

      repository.fetchError = const ApiException(
        kind: ApiErrorKind.network,
        message: 'offline',
      );
      await c.read(brandingControllerProvider.notifier).refresh();
      expect(c.read(brandingControllerProvider).logo, logo);

      repository
        ..fetchError = null
        ..remote = RemoteBranding(
          logo: _asset(BrandAssetKind.logo, 'l2'),
          splash: _asset(BrandAssetKind.splash, 's1'),
        )
        ..failDownloads.add(BrandAssetKind.logo);
      await c.read(brandingControllerProvider.notifier).refresh();
      final state = c.read(brandingControllerProvider);
      expect(state.logo, logo, reason: 'failed download keeps the old logo');
      expect(state.splash?.version, 's1');
    });

    test('parses the API payload', () {
      final remote = RemoteBranding.fromJson({
        'logo': {
          'path': '/branding/assets/logo?v=abc',
          'version': 'abc',
          'contentType': 'image/webp',
        },
        'splash': null,
      });
      expect(remote.logo?.fileExtension, 'webp');
      expect(remote.splash, isNull);
    });
  });

  group('BrandLogo', () {
    Future<void> pump(WidgetTester tester, BrandingState state) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [initialBrandingProvider.overrideWithValue(state)],
            child: const MaterialApp(
              home: Center(child: BrandLogo(width: 200)),
            ),
          ),
        );

    testWidgets('shows the bundled logo by default', (tester) async {
      await pump(tester, BrandingState.defaults);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, BrandLogo.defaultAsset);
      expect(find.bySemanticsLabel('Tirvona Ride'), findsOneWidget);
    });

    testWidgets('shows the admin-set logo when cached', (tester) async {
      await pump(
        tester,
        const BrandingState(
          logo: CachedBrandImage(version: 'l1', filePath: '/x/logo-l1.png'),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as FileImage).file.path, '/x/logo-l1.png');
    });
  });

  group('SplashScreen with an admin-set splash', () {
    testWidgets('shows it full-bleed with the loader near the bottom', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(412, 915)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialBrandingProvider.overrideWithValue(
              const BrandingState(
                splash: CachedBrandImage(
                  version: 's1',
                  filePath: '/x/splash-s1.png',
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: SplashScreen()),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image).first);
      expect((image.image as FileImage).file.path, '/x/splash-s1.png');
      expect(image.fit, BoxFit.cover);
      final centre = tester.getCenter(find.byType(CircularProgressIndicator));
      expect(centre.dx, moreOrLessEquals(206, epsilon: 1));
      expect(centre.dy, moreOrLessEquals(915 * 0.88, epsilon: 1));
    });
  });
}
