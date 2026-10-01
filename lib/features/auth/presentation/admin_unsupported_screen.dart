import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../branding/presentation/brand_logo.dart';
import 'session_controller.dart';

/// Admin accounts operate through the web admin panel only.
class AdminUnsupportedScreen extends ConsumerWidget {
  const AdminUnsupportedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: BrandLogo(width: 220)),
              const SizedBox(height: 24),
              const Icon(
                Icons.admin_panel_settings_outlined,
                size: 56,
                color: AppColors.midnightBlue,
              ),
              const SizedBox(height: 16),
              const Text(
                'Admin accounts use the Tirvona Rides admin panel on the web.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () =>
                    ref.read(sessionControllerProvider.notifier).logout(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
