import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../circuit/application/circuit_providers.dart';
import '../../circuit/domain/circuit_models.dart';
import '../../circuit/presentation/widgets/circuit_widgets.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';

/// Everything a customer needs before booking: stops, what the price
/// includes, how extras are charged, vehicles, passengers, when it runs and
/// the cancellation policy. Nothing about the price is hidden.
class CircuitDetailsScreen extends ConsumerWidget {
  const CircuitDetailsScreen({super.key, required this.packageId});

  final String packageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(circuitPackageProvider(packageId));
    final pkg = async.value;
    if (pkg == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Circuit')),
        body: async.hasError
            ? LoadErrorView(
                error: async.error!,
                onRetry: () =>
                    ref.invalidate(circuitPackageProvider(packageId)),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.templeIvory,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: AppColors.bhagwaDark,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                pkg.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CircuitCover(
                    coverPath: pkg.coverPath,
                    height: 260,
                    borderRadius: BorderRadius.zero,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            sliver: SliverList.list(
              children: [
                Text(
                  '${pkg.city} · ${circuitHeadline(pkg.pricing, pkg.stops.length)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                if (pkg.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(pkg.description),
                ],
                if (!pkg.availableNow) ...[
                  const SizedBox(height: 12),
                  _Banner(
                    text: pkg.unavailableReason ?? 'Not available right now.',
                  ),
                ],
                const SizedBox(height: 16),
                _Section(
                  title: 'Stops',
                  subtitle: 'Visited in this order. Your pickup is where the circuit begins.',
                  child: CircuitStopsTimeline.planned(stops: pkg.stops),
                ),
                _Section(
                  title: 'Price & what\'s included',
                  child: CircuitFareRules(pricing: pkg.pricing),
                ),
                _Section(
                  title: 'Vehicles',
                  child: Column(
                    children: [
                      for (final vehicle in pkg.vehicles)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.bhagwaLight,
                            child: Icon(
                              rideTypeIcon(
                                vehicle.rideType,
                                iconKey: vehicle.icon,
                              ),
                              color: AppColors.bhagwa,
                            ),
                          ),
                          title: Text(
                            vehicle.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Up to ${vehicle.maxPassengers} passenger${vehicle.maxPassengers == 1 ? '' : 's'}',
                          ),
                        ),
                    ],
                  ),
                ),
                _Section(
                  title: 'When it runs',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(
                        Icons.calendar_month,
                        CircuitFormat.days(pkg.days),
                      ),
                      _InfoRow(
                        Icons.schedule,
                        'Book between ${pkg.opensAt} and ${pkg.closesAt}',
                      ),
                      if (pkg.validFrom != null || pkg.validUntil != null)
                        _InfoRow(
                          Icons.event,
                          'Season: ${pkg.validFrom ?? 'now'} – ${pkg.validUntil ?? 'until further notice'}',
                        ),
                    ],
                  ),
                ),
                if (pkg.cancellationPolicy case final policy?
                    when policy.isNotEmpty)
                  _Section(title: 'Cancellation policy', child: Text(policy)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: pkg.availableNow
              ? () => context.push(AppRoutes.customerCircuitBook(pkg.id))
              : null,
          icon: const Icon(Icons.arrow_forward),
          label: Text(pkg.availableNow ? 'Choose pickup' : 'Not available now'),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.midnightBlue,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.bhagwa),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
