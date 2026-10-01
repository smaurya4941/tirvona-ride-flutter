import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/loading_filled_button.dart';
import 'auth_error_messages.dart';
import 'password_reset_flow.dart';
import 'phone_utils.dart';
import 'widgets/otp_verification_panel.dart';
import 'widgets/password_field.dart';

/// Forgot password, step 1: the account's mobile number. [initialPhone]
/// carries over what was typed on the sign-in screen.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialPhone});

  final String? initialPhone;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.initialPhone ?? '');
  bool _submitting = false;
  String? _error;
  bool _noAccount = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
      _noAccount = false;
    });
    try {
      await ref
          .read(passwordResetFlowProvider.notifier)
          .start(normalizePhone(_phone.text));
      if (mounted) await context.push(AppRoutes.forgotPasswordVerify);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.authMessage;
        _noAccount = error.code == AuthErrorCodes.accountNotFound;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                const Center(child: _StepIcon(icon: Icons.lock_reset_rounded)),
                const SizedBox(height: 20),
                Text(
                  'Reset your password',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.midnightBlue,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the mobile number of your account. We will send a '
                  '6-digit code to it on WhatsApp.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _phone,
                  autofocus: widget.initialPhone == null,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Mobile number',
                    prefixIcon: Icon(Icons.phone_outlined),
                    hintText: '98XXXXXXXX',
                    border: OutlineInputBorder(),
                  ),
                  validator: validatePhone,
                ),
                const SizedBox(height: 24),
                ErrorBanner(message: _error),
                if (_noAccount) ...[
                  OutlinedButton.icon(
                    onPressed: () => context.go(AppRoutes.register),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Create an account'),
                  ),
                  const SizedBox(height: 12),
                ],
                LoadingFilledButton(
                  label: 'Send code',
                  icon: Icons.send_rounded,
                  isLoading: _submitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _submitting ? null : () => context.pop(),
                  child: const Text('Back to sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Forgot password, step 2: the WhatsApp code.
class ForgotPasswordOtpScreen extends ConsumerWidget {
  const ForgotPasswordOtpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challenge = ref.watch(
      passwordResetFlowProvider.select((flow) => flow.challenge),
    );
    final flow = ref.read(passwordResetFlowProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: SafeArea(
        child: challenge == null
            ? const _StartOver()
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: OtpVerificationPanel(
                  challenge: challenge,
                  title: 'Enter the reset code',
                  successTitle: 'Code verified',
                  successMessage: 'Now choose a new password…',
                  onChangeNumber: () => context.pop(),
                  onResend: flow.resend,
                  onVerify: (code) async => flow.verify(code),
                  onVerified: () async {
                    if (context.mounted) {
                      context.pushReplacement(AppRoutes.forgotPasswordNew);
                    }
                  },
                ),
              ),
      ),
    );
  }
}

/// Forgot password, step 3: the new password. Success signs this device in
/// (the router then leaves for the role's home) and every other device out.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;
  bool _expired = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(passwordResetFlowProvider.notifier)
          .complete(_password.text);
      // Signed in: the router moves on to the role's home.
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.authMessage;
        _expired = error.code == AuthErrorCodes.passwordResetInvalid;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _startOver() {
    ref.read(passwordResetFlowProvider.notifier).clear();
    context.go(AppRoutes.forgotPassword);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ticket = ref.watch(
      passwordResetFlowProvider.select((flow) => flow.ticket),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('New password')),
      body: SafeArea(
        child: ticket == null
            ? const _StartOver()
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        const Center(
                          child: _StepIcon(icon: Icons.password_rounded),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Choose a new password',
                          textAlign: TextAlign.center,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.midnightBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You will be signed in here and signed out on every '
                          'other device.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyLarge?.copyWith(
                            color: AppColors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),
                        PasswordField(
                          controller: _password,
                          label: 'New password',
                          helperText: passwordRequirements,
                          isNewPassword: true,
                          textInputAction: TextInputAction.next,
                          enabled: !_expired,
                          validator: validateNewPassword,
                        ),
                        const SizedBox(height: 16),
                        PasswordField(
                          controller: _confirm,
                          label: 'Confirm new password',
                          isNewPassword: true,
                          enabled: !_expired,
                          onSubmitted: (_) => _submit(),
                          validator: (value) => value == _password.text
                              ? null
                              : 'Passwords do not match',
                        ),
                        const SizedBox(height: 24),
                        ErrorBanner(message: _error),
                        if (_expired)
                          FilledButton.icon(
                            onPressed: _startOver,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Request a new code'),
                          )
                        else
                          LoadingFilledButton(
                            label: 'Reset password',
                            isLoading: _submitting,
                            onPressed: _submit,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: const BoxDecoration(
        color: AppColors.bhagwaLight,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 34, color: AppColors.bhagwaDark),
    );
  }
}

/// Opened without a reset in progress (e.g. after a restart).
class _StartOver extends StatelessWidget {
  const _StartOver();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_reset_rounded, size: 48),
            const SizedBox(height: 16),
            const Text(
              'There is no password reset in progress.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(AppRoutes.forgotPassword),
              child: const Text('Start again'),
            ),
          ],
        ),
      ),
    );
  }
}
