import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Circular Material-icon badges rendered to bitmaps for Google Maps
/// markers (native markers cannot host Flutter widgets).
///
/// Rendered once per (style, icon, pixel ratio) and cached for the life of
/// the process, so rebuilding a marker set never re-rasterises.
abstract final class MapMarkerIcons {
  static final _cache = <String, Future<BitmapDescriptor>>{};

  /// A coloured disc with a white ring and a white [icon] (pickup, drop).
  static Future<BitmapDescriptor> place({
    required Color color,
    required IconData icon,
    required double devicePixelRatio,
    double size = 44,
  }) => _cached(
    'place:${color.toARGB32()}:${icon.codePoint}:$size:$devicePixelRatio',
    () => _render(
      size: size,
      devicePixelRatio: devicePixelRatio,
      paint: (canvas, s) {
        final c = Offset(s / 2, s / 2);
        _shadow(canvas, c, s / 2 - 1);
        canvas.drawCircle(c, s / 2 - 1, Paint()..color = Colors.white);
        canvas.drawCircle(c, s / 2 - 4, Paint()..color = color);
        _glyph(canvas, icon, c, s * 0.5, Colors.white);
      },
    ),
  );

  /// White disc, dark inner disc, white [icon] pointing north. Rotate it
  /// with `Marker.rotation` (flat marker) to show the heading.
  static Future<BitmapDescriptor> vehicle({
    required Color color,
    required IconData icon,
    required double devicePixelRatio,
    double size = 48,
  }) => _cached(
    'vehicle:${color.toARGB32()}:${icon.codePoint}:$size:$devicePixelRatio',
    () => _render(
      size: size,
      devicePixelRatio: devicePixelRatio,
      paint: (canvas, s) {
        final c = Offset(s / 2, s / 2);
        _shadow(canvas, c, s / 2 - 1);
        canvas.drawCircle(c, s / 2 - 1, Paint()..color = Colors.white);
        canvas.drawCircle(c, s / 2 - 7, Paint()..color = color);
        _glyph(canvas, icon, c, s * 0.42, Colors.white);
      },
    ),
  );

  static Future<BitmapDescriptor> _cached(
    String key,
    Future<BitmapDescriptor> Function() build,
  ) {
    final cached = _cache[key];
    if (cached != null) return cached;
    final future = _cache[key] = build();
    // A failed render is retried next time rather than cached forever.
    future.then<void>(
      (_) {},
      onError: (Object _) {
        _cache.remove(key);
      },
    );
    return future;
  }

  static Future<BitmapDescriptor> _render({
    required double size,
    required double devicePixelRatio,
    required void Function(Canvas canvas, double size) paint,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    paint(canvas, size);
    final pixels = (size * devicePixelRatio).ceil();
    final image = await recorder.endRecording().toImage(pixels, pixels);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.bytes(
        png!.buffer.asUint8List(),
        imagePixelRatio: devicePixelRatio,
      );
    } finally {
      image.dispose();
    }
  }

  static void _shadow(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = Colors.black38
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  static void _glyph(
    Canvas canvas,
    IconData icon,
    Offset center,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }
}
