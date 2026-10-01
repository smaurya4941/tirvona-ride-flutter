import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Five tappable stars (whole numbers only, as the server accepts).
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 44,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var star = 1; star <= 5; star++)
          Semantics(
            button: true,
            selected: star <= value,
            label: '$star star${star == 1 ? '' : 's'}',
            child: IconButton(
              iconSize: size,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              constraints: const BoxConstraints(),
              onPressed: () => onChanged(star),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  star <= value
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  key: ValueKey(star <= value),
                  color: star <= value
                      ? AppColors.sacredGold
                      : AppColors.outlineVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Read-only stars, e.g. "Your rating ★★★★☆".
class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({super.key, required this.value, this.size = 20});

  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value out of 5 stars',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var star = 1; star <= 5; star++)
            Icon(
              star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: star <= value
                  ? AppColors.sacredGold
                  : AppColors.outlineVariant,
            ),
        ],
      ),
    );
  }
}
