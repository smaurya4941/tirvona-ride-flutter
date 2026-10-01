import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/loading_filled_button.dart';
import '../../branding/presentation/brand_logo.dart';
import '../domain/app_user.dart';
import 'auth_error_messages.dart';
import 'phone_utils.dart';
import 'signup_flow.dart';
import 'widgets/password_field.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.customer;
  bool _obscure = true;
  bool _submitting = false;
  String? _error;
  String? _emailError;
  bool _phoneTaken = false;

  @override
  void dispose() {
    for (final controller in [
      _firstName,
      _lastName,
      _phone,
      _email,
      _password,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
      _emailError = null;
      _phoneTaken = false;
    });
    try {
      // No account yet: the server sends a WhatsApp code, and the account
      // is created only once that code is verified on the next screen.
      await ref
          .read(signupFlowProvider.notifier)
          .start(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            phone: normalizePhone(_phone.text),
            email: _email.text.trim(),
            password: _password.text,
            role: _role,
          );
      if (mounted) await context.push(AppRoutes.registerVerify);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.code == AuthErrorCodes.emailAlreadyRegistered) {
          _emailError = error.authMessage;
        } else {
          _error = error.authMessage;
          _phoneTaken = error.code == AuthErrorCodes.phoneAlreadyRegistered;
        }
      });
    } catch (error, stack) {
      // Never fail silently (e.g. a response this build can't read).
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
      if (mounted) {
        setState(
          () => _error =
              'Something went wrong. Please update the app or try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text('Create account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandLogo(width: 180)),
                const SizedBox(height: 16),
                Text(
                  'I want to',
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<UserRole>(
                  segments: const [
                    ButtonSegment(
                      value: UserRole.customer,
                      icon: Icon(Icons.person_outline),
                      label: Text('Book rides'),
                    ),
                    ButtonSegment(
                      value: UserRole.driver,
                      icon: Icon(Icons.drive_eta_outlined),
                      label: Text('Drive'),
                    ),
                  ],
                  selected: {_role},
                  onSelectionChanged: _submitting
                      ? null
                      : (selection) => setState(() => _role = selection.first),
                ),
                if (_role == UserRole.driver) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bhagwaLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'After signing up you\'ll add your license, vehicle and '
                      'KYC documents. Our team reviews them before you can '
                      'start accepting rides.',
                      style: TextStyle(color: AppColors.bhagwaDark),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstName,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.givenName],
                        decoration: const InputDecoration(
                          labelText: 'First name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lastName,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.familyName],
                        decoration: const InputDecoration(
                          labelText: 'Last name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                    labelText: 'Mobile number',
                    prefixIcon: Icon(Icons.phone_outlined),
                    hintText: '98XXXXXXXX',
                    helperText: "We'll send a verification code to this number on WhatsApp",
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (_phoneTaken) setState(() => _phoneTaken = false);
                  },
                  validator: validatePhone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: 'Email (optional)',
                    prefixIcon: const Icon(Icons.mail_outline),
                    border: const OutlineInputBorder(),
                    errorText: _emailError,
                  ),
                  onChanged: (_) {
                    if (_emailError != null) setState(() => _emailError = null);
                  },
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return null;
                    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
                        ? null
                        : 'Enter a valid email';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    helperText: passwordRequirements,
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: validateNewPassword,
                ),
                const SizedBox(height: 24),
                ErrorBanner(message: _error),
                if (_phoneTaken) ...[
                  OutlinedButton.icon(
                    onPressed: () => context.go(AppRoutes.login),
                    icon: const Icon(Icons.login),
                    label: const Text('Log in instead'),
                  ),
                  const SizedBox(height: 12),
                ],
                LoadingFilledButton(
                  label: 'Continue',
                  icon: Icons.arrow_forward,
                  isLoading: _submitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: 12),
                Text(
                  'Next, enter the 6-digit code we send you on WhatsApp.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
