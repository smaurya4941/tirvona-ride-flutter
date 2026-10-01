import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../repository/rating_repository.dart';
import 'star_rating.dart';

/// On a completed ride's details: "Your rating ★★★★★", or "Rate driver" when
/// the server says the ride can still be rated. Hidden otherwise (unpaid
/// rides show the payment card instead).
class RideRatingCard extends ConsumerWidget {
  const RideRatingCard({super.key, required this.rideId});

  final String rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(rideRatingProvider(rideId)).value;
    if (status == null) return const SizedBox.shrink();

    final rating = status.rating;
    if (rating != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.star_rounded, color: AppColors.sacredGold),
          title: const Text('Your rating'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              StarRatingDisplay(value: rating.rating),
              if (rating.comment?.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('“${rating.comment}”'),
                ),
            ],
          ),
        ),
      );
    }
    if (!status.canRate) return const SizedBox.shrink();
    return Card(
      color: AppColors.bhagwaLight,
      child: ListTile(
        leading: const Icon(
          Icons.star_outline_rounded,
          color: AppColors.bhagwa,
        ),
        title: Text('Rate ${status.driver?.name ?? 'your driver'}'),
        subtitle: const Text('How was your ride? It takes 5 seconds.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(AppRoutes.customerRideRating(rideId)),
      ),
    );
  }
}
