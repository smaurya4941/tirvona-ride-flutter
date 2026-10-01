import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/error_banner.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../../shared/widgets/loading_filled_button.dart';
import '../../../rides/application/ride_providers.dart';
import '../models/rating_models.dart';
import '../repository/rating_repository.dart';
import '../widgets/star_rating.dart';

/// Payment Success → Rate your driver. Never forced: "Skip" leaves, and the
/// ride's details offer "Rate driver" later. The server decides whether the
/// ride can be rated (completed, paid, not yet rated).
class RateDriverScreen extends ConsumerStatefulWidget {
  const RateDriverScreen({super.key, required this.rideId});

  final String rideId;

  @override
  ConsumerState<RateDriverScreen> createState() => _RateDriverScreenState();
}

class _RateDriverScreenState extends ConsumerState<RateDriverScreen> {
  final _comment = TextEditingController();
  final Set<String> _tags = {};
  int _stars = 0;
  bool _submitting = false;
  String? _error;
  RideRating? _submitted;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _leave() {
    ref.invalidate(activeRideProvider);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.customerHome);
    }
  }

  String _composedComment() {
    final typed = _comment.text.trim();
    return [..._tags, if (typed.isNotEmpty) typed].join('. ');
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final rating = await ref
          .read(ratingRepositoryProvider)
          .rate(widget.rideId, rating: _stars, comment: _composedComment());
      unawaited(HapticFeedback.mediumImpact());
      ref
        ..invalidate(rideRatingProvider(widget.rideId))
        ..invalidate(rideProvider(widget.rideId));
      if (mounted) setState(() => _submitted = rating);
    } on ApiException catch (error) {
      if (error.code == 'RATING_ALREADY_EXISTS') {
        ref.invalidate(rideRatingProvider(widget.rideId));
      }
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(rideRatingProvider(widget.rideId));
    final status = statusAsync.value;

    final Widget body;
    if (status == null) {
      body = statusAsync.hasError
          ? LoadErrorView(
              error: statusAsync.error!,
              onRetry: () => ref.invalidate(rideRatingProvider(widget.rideId)),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (_submitted != null || status.rating != null) {
      body = _ThankYou(
        rating: _submitted ?? status.rating!,
        driverName: status.driver?.name ?? 'your driver',
        justRated: _submitted != null,
        onDone: _leave,
      );
    } else if (!status.canRate) {
      body = _NotRateable(
        status: status,
        rideId: widget.rideId,
        onDone: _leave,
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          if (status.driver != null) _DriverHeader(driver: status.driver!),
          const SizedBox(height: 28),
          Text(
            'How was your ride?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.midnightBlue,
            ),
          ),
          const SizedBox(height: 12),
          StarRatingInput(
            value: _stars,
            onChanged: (value) => setState(() {
              // Compliments and complaints don't mix: reset on a flip.
              if ((value >= 4) != (_stars >= 4)) _tags.clear();
              _stars = value;
            }),
          ),
          const SizedBox(height: 6),
          Text(
            ratingLabel(_stars),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          if (_stars > 0) ...[
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in ratingSuggestions(_stars))
                  FilterChip(
                    label: Text(tag),
                    selected: _tags.contains(tag),
                    onSelected: (selected) => setState(
                      () => selected ? _tags.add(tag) : _tags.remove(tag),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _comment,
              maxLength: 300,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Add a comment (optional)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ErrorBanner(message: _error),
          LoadingFilledButton(
            label: 'Submit rating',
            isLoading: _submitting,
            onPressed: _stars == 0 ? null : _submit,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _submitting ? null : _leave,
            child: const Text('Skip for now'),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate your driver'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _leave),
      ),
      body: SafeArea(child: body),
    );
  }
}

class _DriverHeader extends StatelessWidget {
  const _DriverHeader({required this.driver});

  final RatedDriver driver;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        CircleAvatar(
          radius: 38,
          backgroundColor: AppColors.bhagwaLight,
          child: Text(
            driver.name.isEmpty ? '?' : driver.name[0].toUpperCase(),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppColors.bhagwaDark,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          driver.name,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        if (driver.registrationNumber != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceSand,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Text(
              driver.registrationNumber!,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
        if (driver.vehicleDescription?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              driver.vehicleDescription!,
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _ThankYou extends StatelessWidget {
  const _ThankYou({
    required this.rating,
    required this.driverName,
    required this.justRated,
    required this.onDone,
  });

  final RideRating rating;
  final String driverName;
  final bool justRated;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        const Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: Color(0xFFFFF7D6),
            child: Icon(
              Icons.favorite_rounded,
              size: 42,
              color: AppColors.sacredGold,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          justRated ? 'Thank you!' : 'Your rating',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Center(child: StarRatingDisplay(value: rating.rating, size: 32)),
        if (rating.comment?.isNotEmpty ?? false) ...[
          const SizedBox(height: 12),
          Text(
            '“${rating.comment}”',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          justRated
              ? 'Your feedback helps $driverName and keeps Tirvona rides safe.'
              : 'You rated $driverName for this ride.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 36),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: onDone,
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _NotRateable extends StatelessWidget {
  const _NotRateable({
    required this.status,
    required this.rideId,
    required this.onDone,
  });

  final RideRatingStatus status;
  final String rideId;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final (String title, String message) = switch (status.reason) {
      RatingBlocker.paymentNotVerified => (
        'Payment pending',
        'You can rate your driver once the payment for this ride is complete.',
      ),
      RatingBlocker.windowClosed => (
        'Rating closed',
        'This ride is too old to be rated.',
      ),
      _ => ('Not available', 'Only completed rides can be rated.'),
    };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.star_border_rounded,
            size: 56,
            color: AppColors.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          if (status.reason == RatingBlocker.paymentNotVerified)
            FilledButton(
              onPressed: () => context.pushReplacement(
                AppRoutes.customerRidePayment(rideId),
              ),
              child: const Text('Pay now'),
            )
          else
            OutlinedButton(onPressed: onDone, child: const Text('Close')),
        ],
      ),
    );
  }
}
