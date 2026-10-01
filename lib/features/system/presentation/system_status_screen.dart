import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/config/app_config_provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/backend_health.dart';
import 'backend_health_provider.dart';

/// Phase 0 landing screen: confirms the app can reach the Tirvona Rides API
/// and that the API can reach its dependencies. Replaced by the auth flow in
/// Phase 1 and kept afterwards as an in-app diagnostics page.
class SystemStatusScreen extends ConsumerWidget {
  const SystemStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final health = ref.watch(backendHealthProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tirvona Rides')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref
              .refresh(backendHealthProvider.future)
              .then((_) {}, onError: (_) {}),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'System status',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                config.apiBaseUrl,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              health.when(
                skipLoadingOnRefresh: false,
                loading: () => const _StatusCard.loading(),
                error: (error, _) => _StatusCard.error(
                  error is ApiException ? error.message : error.toString(),
                ),
                data: _StatusCard.health,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => ref.invalidate(backendHealthProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push(AppRoutes.systemMapCheck),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Check Google Maps'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard.loading() : health = null, errorMessage = null;
  const _StatusCard.error(String this.errorMessage) : health = null;
  const _StatusCard.health(BackendHealth this.health) : errorMessage = null;

  final BackendHealth? health;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final health = this.health;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: switch ((health, errorMessage)) {
          (null, null) => const Row(
            children: [
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Contacting the Tirvona Rides API…'),
            ],
          ),
          (null, final String message) => _Row(
            label: 'API',
            value: message,
            color: AppColors.error,
            icon: Icons.cloud_off,
          ),
          (final BackendHealth report, _) => Column(
            children: [
              _Row(
                label: 'API',
                value: report.isReady
                    ? 'Ready (${report.environment})'
                    : 'Degraded',
                color: report.isReady ? AppColors.success : AppColors.warning,
                icon: report.isReady ? Icons.check_circle : Icons.warning_amber,
              ),
              const Divider(height: 24),
              _DependencyRow(label: 'MongoDB', status: report.database),
              const SizedBox(height: 12),
              _DependencyRow(label: 'Redis', status: report.redis),
            ],
          ),
        },
      ),
    );
  }
}

class _DependencyRow extends StatelessWidget {
  const _DependencyRow({required this.label, required this.status});

  final String label;
  final DependencyStatus status;

  @override
  Widget build(BuildContext context) {
    final (value, color, icon) = switch (status) {
      DependencyStatus.up => (
        'Connected',
        AppColors.success,
        Icons.check_circle,
      ),
      DependencyStatus.down => ('Unreachable', AppColors.error, Icons.error),
      DependencyStatus.disabled => (
        'Not configured',
        AppColors.onSurfaceVariant,
        Icons.remove_circle_outline,
      ),
      DependencyStatus.unknown => (
        'Unknown',
        AppColors.onSurfaceVariant,
        Icons.help_outline,
      ),
    };
    return _Row(label: label, value: value, color: color, icon: icon);
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(value, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
