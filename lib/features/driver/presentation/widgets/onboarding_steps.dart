import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// "1 Profile — 2 Vehicle — 3 Documents" progress header shared by the
/// three driver onboarding screens.
class OnboardingSteps extends StatelessWidget {
  const OnboardingSteps({super.key, required this.current});

  /// Zero-based index of the active step.
  final int current;

  static const _labels = ['Profile', 'Vehicle', 'Documents'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: i <= current
                    ? AppColors.bhagwa
                    : AppColors.outlineVariant,
              ),
            ),
          _Step(index: i, label: _labels[i], current: current),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.label,
    required this.current,
  });

  final int index;
  final String label;
  final int current;

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final active = index == current;
    final color = (done || active)
        ? AppColors.bhagwa
        : AppColors.outlineVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: color,
          child: done
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppColors.midnightBlue : AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
