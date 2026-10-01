import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../branding/application/branding_controller.dart';
import '../../branding/domain/branding.dart';

/// Full-bleed brand splash. Shown while [SessionController] restores the
/// stored session (`SessionStatus.unknown`) and for at least
/// `kSplashMinDuration` (see splash_hold.dart); the router redirects away
/// from it on its own once both are done.
///
/// The bundled artwork is the designed splash with its static spinner
/// removed; a live loader is drawn exactly where the design placed it,
/// whatever the screen's aspect ratio. An admin-set splash (Admin panel →
/// Branding) replaces it from the launch after it was downloaded, with the
/// loader in its bottom 15%, which the upload rules ask to keep clear.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  static const artAsset = 'assets/images/splash_art.png';

  /// Pixel geometry of [artAsset] and of the loader inside it.
  static const _artSize = Size(854, 1842);
  static const _loaderCentre = Offset(430, 1625);
  static const _loaderDiameter = 96.0;
  static const _labelGap = 38.0;

  /// Loader centre on an admin-set splash, as a fraction of screen height.
  static const _customLoaderCentreY = 0.88;
  static const _customLoaderDiameter = 44.0;

  /// Paper colour of the artwork; matches the native launch screen.
  static const _paper = Colors.white;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();

  /// Where the loader block (spinner + label) goes on [screen]. For the
  /// bundled art this mirrors its `BoxFit.cover` mapping; either way the
  /// block stays above the bottom inset on short, wide screens.
  static Rect _loaderRect(
    Size screen,
    EdgeInsets padding, {
    required bool custom,
  }) {
    final double diameter;
    final double centreX;
    double top;
    if (custom) {
      diameter = _customLoaderDiameter;
      centreX = screen.width / 2;
      top = screen.height * _customLoaderCentreY - diameter / 2;
    } else {
      final scale = math.max(
        screen.width / _artSize.width,
        screen.height / _artSize.height,
      );
      final dx = (screen.width - _artSize.width * scale) / 2;
      final dy = (screen.height - _artSize.height * scale) / 2;
      diameter = (_loaderDiameter * scale).clamp(36.0, 56.0);
      centreX = dx + _loaderCentre.dx * scale;
      top = dy + _loaderCentre.dy * scale - diameter / 2;
    }
    final height = diameter + _labelGap;
    const width = 200.0;
    top = math.min(top, screen.height - padding.bottom - 24 - height);
    return Rect.fromLTWH(centreX - width / 2, top, width, height);
  }
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  /// Read once: a splash that changes while it is on screen would flicker.
  /// A newer one downloaded meanwhile shows on the next launch.
  late final CachedBrandImage? _custom = ref
      .read(brandingControllerProvider)
      .splash;

  static const _paper = SplashScreen._paper;

  Widget _fadeIn(
    BuildContext context,
    Widget child,
    int? frame,
    bool syncLoaded,
  ) {
    if (syncLoaded) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      child: child,
    );
  }

  Widget _bundledArt() => Image.asset(
    SplashScreen.artAsset,
    fit: BoxFit.cover,
    alignment: Alignment.center,
    gaplessPlayback: true,
    excludeFromSemantics: true,
    frameBuilder: _fadeIn,
  );

  @override
  Widget build(BuildContext context) {
    final custom = _custom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _paper,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _paper,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final screen = constraints.biggest;
            final padding = MediaQuery.paddingOf(context);
            final loader = SplashScreen._loaderRect(
              screen,
              padding,
              custom: custom != null,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  image: true,
                  label: 'Tirvona Ride. Pilgrim mobility for a better journey.',
                  child: custom == null
                      ? _bundledArt()
                      : Image.file(
                          File(custom.filePath),
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          gaplessPlayback: true,
                          excludeFromSemantics: true,
                          frameBuilder: _fadeIn,
                          errorBuilder: (context, error, stackTrace) =>
                              _bundledArt(),
                        ),
                ),
                // Keeps dark status-bar icons readable over the navy swoosh
                // in the artwork's top-left corner.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: padding.top,
                  child: const IgnorePointer(
                    child: ColoredBox(color: Color(0x99FFFFFF)),
                  ),
                ),
                Positioned.fromRect(rect: loader, child: const _SplashLoader()),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SplashLoader extends StatefulWidget {
  const _SplashLoader();

  @override
  State<_SplashLoader> createState() => _SplashLoaderState();
}

class _SplashLoaderState extends State<_SplashLoader> {
  /// After this long the label admits the wait instead of just "Loading".
  static const _slowAfter = Duration(seconds: 8);
  static const _ink = Color(0xFF12306B);

  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(_slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = _slow ? 'CONNECTING…' : 'LOADING…';
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = constraints.maxHeight - SplashScreen._labelGap;
        return Semantics(
          liveRegion: true,
          label: _slow ? 'Still connecting' : 'Loading',
          child: ExcludeSemantics(
            child: Column(
              children: [
                SizedBox.square(
                  dimension: diameter,
                  child: CircularProgressIndicator(
                    strokeWidth: diameter * 0.1,
                    strokeCap: StrokeCap.round,
                    color: AppColors.bhagwa,
                    backgroundColor: const Color(0xFFDDE3EE),
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    label,
                    key: ValueKey(label),
                    maxLines: 1,
                    textScaler: MediaQuery.textScalerOf(context)
                        .clamp(maxScaleFactor: 1.2),
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
