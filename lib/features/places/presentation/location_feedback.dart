import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';
import '../application/current_location.dart';

/// Explains why "use current location" failed. When only system settings can
/// fix it (GPS off, permission permanently denied) the snackbar opens them.
void showLocationError(BuildContext context, WidgetRef ref, Object error) {
  if (error is! LocationFailure) {
    showErrorSnack(context, error);
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(error.message),
        backgroundColor: AppColors.midnightBlue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: error.needsSettings
            ? SnackBarAction(
                label: 'Settings',
                textColor: AppColors.sacredGold,
                onPressed: () => unawaited(
                  ref.read(deviceLocationProvider).openSettings(error),
                ),
              )
            : null,
      ),
    );
}
