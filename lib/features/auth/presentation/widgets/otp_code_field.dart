import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// Six boxed digits backed by one invisible [TextField], so the keyboard,
/// paste, and one-time-code autofill all behave like a normal input while
/// the user sees separate boxes. Bump [errorSignal] to shake the boxes.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.length = 6,
    this.onCompleted,
    this.enabled = true,
    this.hasError = false,
    this.isSuccess = false,
    this.errorSignal = 0,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final bool hasError;
  final bool isSuccess;
  final int errorSignal;
  final bool autofocus;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField>
    with SingleTickerProviderStateMixin {
  final _focus = FocusNode();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (widget.errorSignal != oldWidget.errorSignal) {
      _shake.forward(from: 0);
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    return Semantics(
      label: 'Verification code, ${widget.length} digits',
      textField: true,
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) => Transform.translate(
          offset: Offset(
            math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value),
            0,
          ),
          child: child,
        ),
        child: Stack(
          children: [
            Row(
              children: [
                for (var index = 0; index < widget.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Expanded(child: _box(index, code)),
                ],
              ],
            ),
            Positioned.fill(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                showCursor: false,
                enableSuggestions: false,
                autocorrect: false,
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                cursorColor: Colors.transparent,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                ),
                onChanged: (value) {
                  if (value.length == widget.length) {
                    widget.onCompleted?.call(value);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(int index, String code) {
    final filled = index < code.length;
    final active =
        _focus.hasFocus &&
        widget.enabled &&
        (index == code.length ||
            (code.length == widget.length && index == widget.length - 1));
    final Color border;
    if (widget.isSuccess) {
      border = AppColors.success;
    } else if (widget.hasError) {
      border = AppColors.error;
    } else if (active) {
      border = AppColors.bhagwa;
    } else if (filled) {
      border = AppColors.midnightBlue.withValues(alpha: 0.4);
    } else {
      border = AppColors.outlineVariant;
    }
    return AspectRatio(
      aspectRatio: 0.82,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.isSuccess
              ? AppColors.success.withValues(alpha: 0.08)
              : (filled ? AppColors.bhagwaLight : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: active ? 2 : 1.4),
        ),
        child: Text(
          filled ? code[index] : '',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.midnightBlue,
          ),
        ),
      ),
    );
  }
}
