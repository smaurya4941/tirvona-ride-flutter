import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/session_controller.dart';

/// Holding screen for drivers who are not yet APPROVED. "Check status"
/// re-fetches /auth/me; if the admin has approved in the meantime, the
/// router moves the driver into [DriverShell] automatically.
class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  bool _checking = false;

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    await ref.read(sessionControllerProvider.notifier).refreshUser();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).user;
    final driver = user?.driver;
    final status = driver?.driverStatus ?? DriverStatus.pending;
    final view = _StatusView.forStatus(status);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver account'),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).logout(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _checkStatus,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              CircleAvatar(
                radius: 44,
                backgroundColor: view.color.withValues(alpha: 0.12),
                child: Icon(view.icon, size: 44, color: view.color),
              ),
              const SizedBox(height: 24),
              Text(
                view.title,
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.midnightBlue,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                view.body,
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              if (status == DriverStatus.rejected &&
                  driver?.rejectionReason != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reason',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(driver!.rejectionReason!),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              if (status == DriverStatus.rejected)
                FilledButton.icon(
                  onPressed: () => context.go(AppRoutes.driverRegistration),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Update & resubmit'),
                )
              else
                FilledButton.icon(
                  onPressed: _checking ? null : _checkStatus,
                  icon: _checking
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Check status'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusView {
  const _StatusView(this.icon, this.color, this.title, this.body);

  factory _StatusView.forStatus(DriverStatus status) => switch (status) {
    DriverStatus.underReview => const _StatusView(
      Icons.hourglass_top_rounded,
      AppColors.bhagwa,
      'Pending approval',
      'Thanks! Your documents are with our team. We usually review new '
          'drivers within 24–48 hours. You\'ll be able to accept rides once '
          'approved.',
    ),
    DriverStatus.rejected => const _StatusView(
      Icons.cancel_outlined,
      AppColors.error,
      'Application not approved',
      'Please review the reason below, fix your details or documents and '
          'submit again.',
    ),
    DriverStatus.suspended => const _StatusView(
      Icons.block,
      AppColors.error,
      'Account suspended',
      'Your driver account has been suspended. Please contact Tirvona '
          'support for help.',
    ),
    DriverStatus.pending || DriverStatus.approved => const _StatusView(
      Icons.info_outline,
      AppColors.midnightBlue,
      'Finish your application',
      'Complete your details, vehicle and documents to submit for review.',
    ),
  };

  final IconData icon;
  final Color color;
  final String title;
  final String body;
}
