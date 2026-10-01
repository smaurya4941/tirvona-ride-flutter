import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/branding_controller.dart';

/// The Tirvona Ride logo: the admin-set one when there is one, otherwise the
/// logo bundled with the app. Designed for light backgrounds.
class BrandLogo extends ConsumerWidget {
  const BrandLogo({super.key, this.width, this.height});

  static const defaultAsset = 'assets/images/logo.png';
  static const semanticLabel = 'Tirvona Ride';

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = ref.watch(brandingControllerProvider).logo;
    final fallback = Image.asset(
      defaultAsset,
      width: width,
      height: height,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
    );
    if (custom == null) return fallback;
    return Image.file(
      File(custom.filePath),
      // A new version is a new file path, so the image cache never serves
      // the previous logo.
      key: ValueKey(custom.filePath),
      width: width,
      height: height,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
