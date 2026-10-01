import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/error_banner.dart';
import '../../../../shared/widgets/loading_filled_button.dart';
import '../../domain/otp_challenge.dart';
import '../auth_error_messages.dart';
import '../phone_utils.dart';
import 'otp_code_field.dart';

/// WhatsApp's brand green, used only to signal the delivery channel.
const _whatsappGreen = Color(0xFF25D366);

/// The "enter the code we sent on WhatsApp" experience, shared by signup,
/// login with a code, forgot password and older accounts verifying their
/// number. It owns the input, the
/// expiry and resend countdowns, and the error states; the screen supplies
/// what verify/resend mean.
///
/// Countdowns are UI only — the server decides whether a code is valid or
/// a resend is allowed, and its answers (e.g. retryAfterSeconds) win.
class OtpVerificationPanel extends StatefulWidget {
  const OtpVerificationPanel({
    super.key,
    required this.challenge,
    required this.onVerify,
    required this.onResend,
    required this.onVerified,
    this.onChangeNumber,
    this.onSessionInvalid,
    this.title = 'Verify your phone',
    this.successTitle = 'Phone verified',
    this.successMessage = 'Setting up your account…',
  });

  /// Headline above the code field, and the copy of the success state.
  final String title;
  final String successTitle;
  final String successMessage;

  final OtpChallenge challenge;

  /// Throws [ApiException] when the server rejects the code.
  final Future<void> Function(String code) onVerify;

  /// Throws [ApiException] when the server refuses to send.
  final Future<OtpChallenge> Function() onResend;

  /// Runs after the success state has been shown.
  final Future<void> Function() onVerified;
  final VoidCallback? onChangeNumber;

  /// The sign-up this code belonged to is gone (expired or replaced).
  final ValueChanged<String>? onSessionInvalid;

  @override
  State<OtpVerificationPanel> createState() => _OtpVerificationPanelState();
}

class _OtpVerificationPanelState extends State<OtpVerificationPanel> {
  final _code = TextEditingController();
  late OtpChallenge _challenge = widget.challenge;
  Timer? _ticker;
  DateTime _now = DateTime.now();
  bool _verifying = false;
  bool _resending = false;
  bool _verified = false;
  String? _error;
  String? _notice;
  int _errorSignal = 0;

  /// Set when the server says this code can no longer succeed.
  bool _codeDead = false;

  /// Resend is blocked for the whole window (per-number send cap).
  DateTime? _sendLimitUntil;

  @override
  void initState() {
    super.initState();
    if (!_challenge.codeSent) {
      _notice =
          'We sent you a code a moment ago. Use that one, or request a new '
          'code when the timer ends.';
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(OtpVerificationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.challenge != oldWidget.challenge) _challenge = widget.challenge;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  Duration get _expiresIn => _positive(_challenge.expiresAt.difference(_now));
  Duration get _resendIn {
    final until = _sendLimitUntil ?? _challenge.resendAvailableAt;
    return _positive(until.difference(_now));
  }

  bool get _expired => _expiresIn == Duration.zero;

  static Duration _positive(Duration value) =>
      value.isNegative ? Duration.zero : value;

  static String _clock(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _verify([String? value]) async {
    final code = value ?? _code.text;
    if (_verifying || _verified) return;
    if (code.length != _challenge.codeLength) {
      setState(() => _error = 'Enter the ${_challenge.codeLength}-digit code');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.onVerify(code);
      if (!mounted) return;
      setState(() => _verified = true);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await widget.onVerified();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == AuthErrorCodes.signupSessionInvalid &&
          widget.onSessionInvalid != null) {
        widget.onSessionInvalid!(error.authMessage);
        return;
      }
      setState(() {
        _error = error.authMessage;
        _errorSignal++;
        _codeDead = error.needsNewCode;
        _code.clear();
      });
    } catch (error, stack) {
      _reportUnexpected(error, stack);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (_resending || _resendIn > Duration.zero) return;
    setState(() {
      _resending = true;
      _error = null;
      _notice = null;
    });
    try {
      final challenge = await widget.onResend();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _codeDead = false;
        _sendLimitUntil = null;
        _code.clear();
        // The server keeps a code sent moments ago instead of sending another.
        _notice = challenge.codeSent
            ? 'New code sent on WhatsApp. Earlier codes no longer work.'
            : 'We sent you a code a moment ago. Use that one, or request a '
                  'new code when the timer ends.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == AuthErrorCodes.signupSessionInvalid &&
          widget.onSessionInvalid != null) {
        widget.onSessionInvalid!(error.authMessage);
        return;
      }
      final wait = error.retryAfter;
      setState(() {
        _error = error.authMessage;
        if (wait != null && error.code == AuthErrorCodes.otpSendLimitReached) {
          _sendLimitUntil = DateTime.now().add(wait);
        } else if (wait != null) {
          _challenge = _challenge.withResendAvailableIn(wait);
        }
      });
    } catch (error, stack) {
      _reportUnexpected(error, stack);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// Anything that isn't an API answer (a bug, an unreadable response):
  /// report it and tell the user instead of doing nothing.
  void _reportUnexpected(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    if (!mounted) return;
    setState(() {
      _verified = false;
      _error = 'Something went wrong. Please try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _verified
          ? _SuccessView(
              key: const ValueKey('verified'),
              title: widget.successTitle,
              message: widget.successMessage,
            )
          : Column(
              key: const ValueKey('form'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: _ChannelBadge()),
                const SizedBox(height: 20),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.midnightBlue,
                  ),
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    text:
                        'We sent a ${_challenge.codeLength}-digit code on '
                        'WhatsApp to\n',
                    children: [
                      TextSpan(
                        text: formatPhoneForDisplay(_challenge.phone),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.midnightBlue,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (widget.onChangeNumber != null)
                  Center(
                    child: TextButton(
                      onPressed: _verifying ? null : widget.onChangeNumber,
                      child: const Text('Change number'),
                    ),
                  )
                else
                  const SizedBox(height: 16),
                const SizedBox(height: 12),
                OtpCodeField(
                  controller: _code,
                  length: _challenge.codeLength,
                  enabled: !_verifying,
                  hasError: _error != null,
                  errorSignal: _errorSignal,
                  onCompleted: _verify,
                ),
                const SizedBox(height: 12),
                _ExpiryLine(expired: _expired, remaining: _clock(_expiresIn)),
                const SizedBox(height: 20),
                if (_notice != null) _NoticeBanner(message: _notice!),
                ErrorBanner(message: _error),
                LoadingFilledButton(
                  label: 'Verify',
                  isLoading: _verifying,
                  onPressed: (_expired || _codeDead) ? null : _verify,
                ),
                const SizedBox(height: 20),
                _ResendRow(
                  waiting: _resendIn,
                  resending: _resending,
                  emphasise: _expired || _codeDead,
                  sendsRemaining: _challenge.sendsRemaining,
                  onResend: _resend,
                  clock: _clock,
                ),
                const SizedBox(height: 16),
                Text(
                  'Open WhatsApp and look for a message from Tirvona Rides. '
                  'Never share this code with anyone — Tirvona will never '
                  'ask for it.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: _whatsappGreen.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.forum_rounded,
        size: 34,
        color: Color(0xFF128C7E),
      ),
    );
  }
}

class _ExpiryLine extends StatelessWidget {
  const _ExpiryLine({required this.expired, required this.remaining});

  final bool expired;
  final String remaining;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          expired ? Icons.timer_off_outlined : Icons.timer_outlined,
          size: 18,
          color: expired ? AppColors.error : AppColors.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          expired ? 'Code expired' : 'Code expires in $remaining',
          style: style?.copyWith(
            color: expired ? AppColors.error : AppColors.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ResendRow extends StatelessWidget {
  const _ResendRow({
    required this.waiting,
    required this.resending,
    required this.emphasise,
    required this.sendsRemaining,
    required this.onResend,
    required this.clock,
  });

  final Duration waiting;
  final bool resending;
  final bool emphasise;
  final int sendsRemaining;
  final VoidCallback onResend;
  final String Function(Duration) clock;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canResend = waiting == Duration.zero && !resending;
    final label = resending
        ? 'Sending…'
        : waiting > Duration.zero
        ? 'Resend available in ${waiting.inSeconds < 60 ? '${waiting.inSeconds}s' : clock(waiting)}'
        : 'Resend code';
    return Column(
      children: [
        Text(
          "Didn't receive the code?",
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        if (emphasise && canResend)
          OutlinedButton.icon(
            onPressed: onResend,
            icon: const Icon(Icons.refresh),
            label: Text(label),
          )
        else
          TextButton(
            onPressed: canResend ? onResend : null,
            child: Text(
              label,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        if (sendsRemaining > 0 && sendsRemaining <= 2)
          Text(
            '$sendsRemaining more ${sendsRemaining == 1 ? 'code' : 'codes'} '
            'can be sent to this number for now',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.success,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 52,
                color: AppColors.success,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.midnightBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: textTheme.bodyLarge?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
