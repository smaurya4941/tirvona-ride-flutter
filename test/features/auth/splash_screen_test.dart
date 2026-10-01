import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/features/auth/presentation/splash_hold.dart';
import 'package:tirvona_ride/features/auth/presentation/splash_screen.dart';

void main() {
  group('SplashHold', () {
    testWidgets('holds for the minimum duration, then releases', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          splashMinDurationProvider.overrideWithValue(
            const Duration(milliseconds: 500),
          ),
        ],
      );
      addTearDown(container.dispose);
      final seen = <bool>[];
      container.listen(
        splashHoldProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );

      await tester.pump(const Duration(milliseconds: 499));
      expect(container.read(splashHoldProvider), isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(container.read(splashHoldProvider), isFalse);
      expect(seen, [true, false]);
    });

    test('a zero duration never holds', () {
      final container = ProviderContainer(
        overrides: [splashMinDurationProvider.overrideWithValue(Duration.zero)],
      );
      addTearDown(container.dispose);
      expect(container.read(splashHoldProvider), isFalse);
    });
  });

  group('SplashScreen', () {
    Future<void> pumpOn(WidgetTester tester, Size size) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SplashScreen())),
      );
    }

    testWidgets('shows the artwork and a live loader', (tester) async {
      await pumpOn(tester, const Size(412, 915));

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, SplashScreen.artAsset);
      expect(image.fit, BoxFit.cover);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('LOADING…'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });

    testWidgets('puts the loader where the artwork placed it', (tester) async {
      await pumpOn(tester, const Size(412, 915));

      // 915 / 1842 is the cover scale on this screen (height-bound).
      const scale = 915 / 1842;
      final centre = tester.getCenter(find.byType(CircularProgressIndicator));
      const artLeft = (412 - 854 * scale) / 2;
      expect(centre.dx, moreOrLessEquals(artLeft + 430 * scale, epsilon: 1));
      expect(centre.dy, moreOrLessEquals(1625 * scale, epsilon: 1));
    });

    testWidgets('keeps the loader on screen when the art is cropped', (
      tester,
    ) async {
      // Tablet-ish: width-bound, so the art's bottom is cut off.
      await pumpOn(tester, const Size(800, 1000));

      final label = tester.getRect(find.text('LOADING…'));
      expect(label.bottom, lessThanOrEqualTo(1000));
      expect(tester.takeException(), isNull);
    });

    testWidgets('admits a slow start after a while', (tester) async {
      await pumpOn(tester, const Size(412, 915));

      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('CONNECTING…'), findsOneWidget);
      expect(find.bySemanticsLabel('Still connecting'), findsOneWidget);
    });
  });
}
