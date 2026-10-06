import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../circuit/application/circuit_providers.dart';
import '../../circuit/domain/circuit_models.dart';
import '../../circuit/presentation/widgets/circuit_widgets.dart';
import '../../rides/domain/ride_formatters.dart';

/// "Ride Circuit": the packages customers can book — several temples or
/// sights in one booking, with a vehicle and driver for a fixed time and
/// distance.
class CircuitListScreen extends ConsumerWidget {
  const CircuitListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packages = ref.watch(circuitPackagesProvider);
    return Scaffold(
      backgroundColor: AppColors.templeIvory,
      appBar: AppBar(title: const Text('Ride Circuit')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(circuitPackagesProvider.future),
        child: packages.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => LoadErrorView(
            error: error,
            onRetry: () => ref.invalidate(circuitPackagesProvider),
          ),
          data: (items) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 16),
                child: Text(
                  'Visit several destinations in one booking. Your vehicle and '
                  'driver stay with you for the whole circuit.',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                ),
              ),
              if (items.isEmpty)
                const _EmptyState()
              else
                for (final pkg in items) ...[
                  CircuitPackageCard(
                    package: pkg,
                    onTap: () =>
                        context.push(AppRoutes.customerCircuit(pkg.id)),
                  ),
                  const SizedBox(height: 16),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class CircuitPackageCard extends StatelessWidget {
  const CircuitPackageCard({
    super.key,
    required this.package,
    required this.onTap,
  });

  final CircuitPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shown = package.stops.take(3).toList();
    final more = package.stops.length - shown.length;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CircuitCover(coverPath: package.coverPath),
                Positioned(
                  left: 12,
                  top: 12,
                  child: _Chip(label: package.city, icon: Icons.location_city),
                ),
                if (!package.availableNow)
                  const Positioned(
                    right: 12,
                    top: 12,
                    child: _Chip(label: 'Closed now', icon: Icons.schedule),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    package.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.midnightBlue,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final stop in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.place,
                            size: 16,
                            color: AppColors.bhagwa,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              stop.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (more > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 22),
                      child: Text(
                        '+$more more',
                        style: const TextStyle(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    circuitHeadline(package.pricing, package.stops.length),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (package.hasPriceRange) ...[
                        const Text(
                          'from',
                          style: TextStyle(color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        RideFormat.money(package.pricing.basePrice),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.bhagwaDark,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'package',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                      const Spacer(),
                      FilledButton.tonal(
                        // Compact: the theme's buttons are full width by default.
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        onPressed: onTap,
                        child: const Text('View details'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(Icons.temple_hindu, size: 56, color: AppColors.outlineVariant),
          SizedBox(height: 12),
          Text(
            'No circuits available right now',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(
            'New circuits appear here as soon as they are published.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
