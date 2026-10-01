import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../features/account/presentation/widgets/profile_avatar.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/branding/presentation/brand_logo.dart';
import '../../features/notifications/state/notification_providers.dart';

/// Profile tab shared by the customer and driver shells. [extra] lets each
/// shell add role-specific rows (e.g. the driver code); [header] goes above
/// the account card (e.g. the driver's rating).
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key, this.extra = const [], this.header = const []});

  final List<Widget> extra;
  final List<Widget> header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    if (user == null) return const SizedBox.shrink();
    final isDriver = user.role == UserRole.driver;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Semantics(
            button: true,
            label: 'Edit profile',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.push(AppRoutes.editProfileFor(isDriver)),
              child: ProfileAvatar(user: user),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          user.displayName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Center(
          child: TextButton.icon(
            onPressed: () => context.push(AppRoutes.editProfileFor(isDriver)),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit profile'),
          ),
        ),
        const SizedBox(height: 12),
        ...header,
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: const Text('Mobile'),
                subtitle: Text(user.phone),
                trailing: user.isPhoneVerified
                    ? const Icon(Icons.verified, color: AppColors.success)
                    : null,
              ),
              if (user.email != null)
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('Email'),
                  subtitle: Text(user.email!),
                ),
              ...extra,
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SafetyAndSupportCard(isDriver: isDriver),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              if (!isDriver)
                ListTile(
                  leading: const Icon(Icons.bookmark_border_rounded),
                  title: const Text('Saved places'),
                  subtitle: const Text('Home, Work and your own places'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.customerSavedPlaces),
                ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                subtitle: const Text('Password, permissions, devices'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.settingsFor(isDriver)),
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.error),
                title: const Text(
                  'Sign out',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () =>
                    ref.read(sessionControllerProvider.notifier).logout(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Center(child: BrandLogo(width: 150)),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Notifications, emergency contacts and help — the same rows for both
/// roles, each opening the role's own screen.
class _SafetyAndSupportCard extends ConsumerWidget {
  const _SafetyAndSupportCard({required this.isDriver});

  final bool isDriver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unread > 0) Badge(label: Text('$unread')),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => context.push(AppRoutes.notificationsFor(isDriver)),
          ),
          ListTile(
            leading: const Icon(Icons.contact_emergency_outlined),
            title: const Text('Emergency contacts'),
            subtitle: const Text('Who we reach if you press SOS'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.emergencyContactsFor(isDriver)),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Help & support'),
            subtitle: const Text('Report an issue, see your complaints'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.supportFor(isDriver)),
          ),
        ],
      ),
    );
  }
}
