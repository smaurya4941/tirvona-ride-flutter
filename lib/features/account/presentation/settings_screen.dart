import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/phone_utils.dart';
import '../../auth/presentation/session_controller.dart';
import '../../branding/presentation/brand_logo.dart';
import 'widgets/profile_avatar.dart';

/// Whether the app may use the device location, re-read each time Settings
/// opens (the user may have changed it in system settings meanwhile).
final locationPermissionProvider = FutureProvider.autoDispose<LocationPermission?>((
  ref,
) async {
  try {
    return await Geolocator.checkPermission();
  } on Object {
    return null;
  }
});

/// Account, security, permissions and app information for both roles.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, required this.isDriver});

  final bool isDriver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    if (user == null) return const Scaffold();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _AccountHeader(
            user: user,
            onTap: () => context.push(AppRoutes.editProfileFor(isDriver)),
          ),
          const _SectionTitle('Account'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Edit profile'),
                  subtitle: const Text('Name, email, photo'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.editProfileFor(isDriver)),
                ),
                ListTile(
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Change password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.push(AppRoutes.changePasswordFor(isDriver)),
                ),
                if (!isDriver)
                  ListTile(
                    leading: const Icon(Icons.bookmark_border_rounded),
                    title: const Text('Saved places'),
                    subtitle: const Text('Home, Work and your own places'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.customerSavedPlaces),
                  ),
              ],
            ),
          ),
          const _SectionTitle('Notifications & permissions'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  subtitle: const Text('Ride updates and announcements'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.push(AppRoutes.notificationsFor(isDriver)),
                ),
                _LocationPermissionTile(isDriver: isDriver),
              ],
            ),
          ),
          const _SectionTitle('Security'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices_other_outlined),
              title: const Text('Sign out of all devices'),
              subtitle: const Text(
                'Use this if you lost a phone or shared your password',
              ),
              onTap: () => _signOutEverywhere(context, ref),
            ),
          ),
          const _SectionTitle('About'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: const Text('System status'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.systemStatus),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About Tirvona Rides'),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Tirvona Rides',
                    applicationIcon: const BrandLogo(width: 96),
                    applicationLegalese: '© Tirvona',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOutEverywhere(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.devices_other_outlined),
        title: const Text('Sign out of all devices?'),
        content: const Text(
          'You will be signed out on every phone, including this one. '
          'Sign in again with your password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out everywhere'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(sessionControllerProvider.notifier).logoutEverywhere();
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.user, required this.onTap});

  final AppUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ProfileAvatar(user: user, radius: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatPhoneForDisplay(user.phone),
                      style: const TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                    if (user.email != null)
                      Text(
                        user.email!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationPermissionTile extends ConsumerWidget {
  const _LocationPermissionTile({required this.isDriver});

  final bool isDriver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(locationPermissionProvider).value;
    final (status, granted) = switch (permission) {
      LocationPermission.always => ('Allowed all the time', true),
      LocationPermission.whileInUse => ('Allowed while using the app', true),
      LocationPermission.denied ||
      LocationPermission.deniedForever => ('Not allowed', false),
      _ => ('Checking…', true),
    };
    return ListTile(
      leading: const Icon(Icons.location_on_outlined),
      title: const Text('Location & app permissions'),
      subtitle: Text(
        granted
            ? status
            : isDriver
            ? '$status — needed to receive and track rides'
            : '$status — needed to find your pickup',
        style: granted ? null : const TextStyle(color: AppColors.error),
      ),
      trailing: const Icon(Icons.open_in_new_rounded),
      onTap: () async {
        await Geolocator.openAppSettings();
        ref.invalidate(locationPermissionProvider);
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
