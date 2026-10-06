import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../auth/presentation/auth_error_messages.dart';
import '../../auth/presentation/widgets/password_field.dart';
import '../../legal/legal_links.dart';
import '../application/account_controller.dart';

/// Permanent account deletion (Google Play requires it in the app). The
/// person re-enters their password; on success the account is gone and the
/// router sends this device back to the login screen.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key, required this.isDriver});

  final bool isDriver;

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever_outlined,
          color: AppColors.error,
          size: 32,
        ),
        title: const Text('Delete your account?'),
        content: const Text(
          'This cannot be undone. Your profile and personal details are '
          'erased and you are signed out on every device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep my account'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      // Signing out flips the router to the login screen; nothing to pop.
      await ref
          .read(accountControllerProvider)
          .deleteAccount(password: _password.text);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = switch (error.code) {
          AuthErrorCodes.accountDeletionPasswordInvalid =>
            'That password is not correct.',
          _ => error.authMessage,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final erased = <String>[
      'Your name, mobile number, email, date of birth and photo',
      'Saved places, emergency contacts and notifications',
      if (widget.isDriver) 'Your licence details, documents and vehicle',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Text('What happens', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final item in erased)
                _Bullet(icon: Icons.delete_outline, text: item),
              const SizedBox(height: 4),
              const _Bullet(
                icon: Icons.receipt_long_outlined,
                text:
                    'Trip, payment and earning records are kept without your '
                    'name or contact details, as the law requires.',
              ),
              const _Bullet(
                icon: Icons.phone_iphone_outlined,
                text: 'You can sign up again later with the same number.',
              ),
              const SizedBox(height: 12),
              Text(
                widget.isDriver
                    ? 'We cannot delete while you have a ride in progress or '
                          'earnings that are not yet paid out.'
                    : 'We cannot delete while you have a ride in progress or '
                          'an unpaid cancellation fee.',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              PasswordField(
                controller: _password,
                label: 'Your password',
                enabled: !_deleting,
                onSubmitted: (_) => _submit(),
                validator: (value) =>
                    (value ?? '').isEmpty ? 'Enter your password' : null,
              ),
              const SizedBox(height: 20),
              ErrorBanner(message: _error),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: _deleting ? null : _submit,
                icon: _deleting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_forever_outlined),
                label: const Text('Delete my account'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    openLegalPage(context, ref, LegalPage.deleteAccount),
                child: const Text('More about account deletion'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
