import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/date_field.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../ratings/driver_ratings.dart';
import '../data/driver_account_repository.dart';
import '../domain/driver_change.dart';

/// Which ratings the list shows.
@immutable
class _ReviewFilter {
  const _ReviewFilter({this.stars, this.withComment = false});

  final int? stars;
  final bool withComment;

  @override
  bool operator ==(Object other) =>
      other is _ReviewFilter &&
      other.stars == stars &&
      other.withComment == withComment;

  @override
  int get hashCode => Object.hash(stars, withComment);
}

/// The driver's average with its breakdown, then every rating newest first
/// — stars, comment and day only, so riders stay anonymous.
class DriverReviewsScreen extends ConsumerStatefulWidget {
  const DriverReviewsScreen({super.key});

  @override
  ConsumerState<DriverReviewsScreen> createState() =>
      _DriverReviewsScreenState();
}

class _DriverReviewsScreenState extends ConsumerState<DriverReviewsScreen> {
  static const _pageSize = 20;

  final _scroll = ScrollController();
  final _items = <DriverReview>[];
  _ReviewFilter _filter = const _ReviewFilter();
  String? _cursor;
  bool _loading = false;
  bool _done = false;
  Object? _error;

  /// Bumped on every filter change, so a late page of the old filter is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(driverAccountRepositoryProvider)
          .reviews(
            cursor: _cursor,
            limit: _pageSize,
            stars: _filter.stars,
            withComment: _filter.withComment,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
      });
    } on Object catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _reset(_ReviewFilter filter) async {
    setState(() {
      _generation++;
      _filter = filter;
      _items.clear();
      _cursor = null;
      _done = false;
      _loading = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _refresh() async {
    ref.invalidate(driverRatingSummaryProvider);
    await _reset(_filter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ratings & reviews')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const DriverRatingCard(),
            const SizedBox(height: 12),
            const Text(
              'Riders rate you after paying. Reviews are anonymous: you see '
              'the stars, the comment and the day, never who wrote it.',
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _filter == const _ReviewFilter(),
                    onSelected: () => _reset(const _ReviewFilter()),
                  ),
                  _FilterChip(
                    label: 'With comments',
                    selected: _filter.withComment,
                    onSelected: () => _reset(
                      _ReviewFilter(
                        stars: _filter.stars,
                        withComment: !_filter.withComment,
                      ),
                    ),
                  ),
                  for (var star = 5; star >= 1; star--)
                    _FilterChip(
                      label: '$star ★',
                      selected: _filter.stars == star,
                      onSelected: () => _reset(
                        _ReviewFilter(
                          stars: _filter.stars == star ? null : star,
                          withComment: _filter.withComment,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final review in _items) _ReviewTile(review: review),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              LoadErrorView(error: _error!, onRetry: _loadMore)
            else if (_done && _items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const Icon(
                      Icons.reviews_outlined,
                      size: 44,
                      color: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _filter == const _ReviewFilter()
                          ? 'No ratings yet. They appear here after riders rate '
                                'their trips.'
                          : 'No ratings match this filter.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.onSurfaceVariant),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
    ),
  );
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final DriverReview review;

  @override
  Widget build(BuildContext context) {
    final comment = review.comment;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Semantics(
                  label: '${review.rating} out of 5 stars',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      for (var star = 1; star <= 5; star++)
                        Icon(
                          star <= review.rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 18,
                          color: AppColors.sacredGold,
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  formatDate(review.ratedOn),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('“$comment”'),
            ],
          ],
        ),
      ),
    );
  }
}
