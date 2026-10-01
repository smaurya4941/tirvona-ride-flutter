import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/loading_filled_button.dart';
import '../../auth/presentation/auth_error_messages.dart';
import '../../auth/presentation/session_controller.dart';
import '../../auth/presentation/widgets/password_field.dart';
import '../application/account_controller.dart';

/// Change password with the current one. A user who forgot it can reset it
/// with a WhatsApp code instead (link below the form).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(accountControllerProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _password.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password changed')));
      context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.code == AuthErrorCodes.invalidCredentials
            ? 'Your current password is not correct.'
            : error.authMessage,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Forgot the current one: reset over WhatsApp, signed out here first.
  Future<void> _forgot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset with a WhatsApp code?'),
        content: const Text(
          'You will be signed out, then we will send a code to your mobile '
          'number so you can choose a new password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final phone = ref.read(sessionControllerProvider).user?.phone;
    final router = GoRouter.of(context);
    await ref.read(sessionControllerProvider.notifier).logout();
    router.go(
      phone == null
          ? AppRoutes.forgotPassword
          : AppRoutes.forgotPasswordFor(phone),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                PasswordField(
                  controller: _current,
                  label: 'Current password',
                  textInputAction: TextInputAction.next,
                  validator: (value) => (value ?? '').isEmpty
                      ? 'Enter your current password'
                      : null,
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _password,
                  label: 'New password',
                  helperText: passwordRequirements,
                  isNewPassword: true,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final problem = validateNewPassword(value);
                    if (problem != null) return problem;
                    return value == _current.text
                        ? 'Choose a password different from the current one'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _confirm,
                  label: 'Confirm new password',
                  isNewPassword: true,
                  onSubmitted: (_) => _submit(),
                  validator: (value) => value == _password.text
                      ? null
                      : 'Passwords do not match',
                ),
                const SizedBox(height: 24),
                ErrorBanner(message: _error),
                LoadingFilledButton(
                  label: 'Change password',
                  isLoading: _saving,
                  onPressed: _submit,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _saving ? null : _forgot,
                  child: const Text('Forgot your current password?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
