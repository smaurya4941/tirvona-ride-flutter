import 'package:flutter/material.dart';

/// A [FilledButton] that shows a spinner and disables itself while
/// [isLoading] is true — the same submit-button pattern every auth/driver
/// form in this app needs.
class LoadingFilledButton extends StatelessWidget {
  const LoadingFilledButton({
    super.key,
    required this.label,
    required this.isLoading,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          )
        : Text(label);

    if (icon == null) {
      return FilledButton(
        onPressed: isLoading ? null : onPressed,
        child: child,
      );
    }
    return FilledButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading ? const SizedBox.shrink() : Icon(icon),
      label: child,
    );
  }
}
