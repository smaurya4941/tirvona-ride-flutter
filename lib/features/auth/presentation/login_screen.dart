import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/loading_filled_button.dart';
import '../../branding/presentation/brand_logo.dart';
import 'auth_error_messages.dart';
import 'login_otp_flow.dart';
import 'phone_utils.dart';
import 'session_controller.dart';

/// Sign in with the mobile number and either the password or a code sent
/// on WhatsApp. The screen opens on the method the user picked last time.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  /// The number has no account (WhatsApp code mode): offer sign-up.
  bool _noAccount = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _chooseMethod(LoginMethod method) {
    setState(() {
      _error = null;
      _noAccount = false;
    });
    ref.read(loginMethodPreferenceProvider.notifier).choose(method);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final method = ref.read(loginMethodPreferenceProvider);
    setState(() {
      _submitting = true;
      _error = null;
      _noAccount = false;
    });
    try {
      if (method == LoginMethod.whatsappOtp) {
        FocusScope.of(context).unfocus();
        await ref
            .read(loginOtpFlowProvider.notifier)
            .start(normalizePhone(_phone.text));
        if (mounted) await context.push(AppRoutes.loginVerify);
      } else {
        // On success the router's redirect takes over and routes by role.
        await ref
            .read(sessionControllerProvider.notifier)
            .login(
              phone: normalizePhone(_phone.text),
              password: _password.text,
            );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (method == LoginMethod.whatsappOtp) {
          _error = error.authMessage;
          _noAccount = error.code == AuthErrorCodes.accountNotFound;
        } else {
          _error = error.message;
        }
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Carries a valid number over, so the user does not type it twice.
  void _forgotPassword() {
    final phone = normalizePhone(_phone.text);
    context.push(
      validatePhone(_phone.text) == null
          ? AppRoutes.forgotPasswordFor(phone)
          : AppRoutes.forgotPassword,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final method = ref.watch(loginMethodPreferenceProvider);
    final withCode = method == LoginMethod.whatsappOtp;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLogo(width: 260)),
                  const SizedBox(height: 20),
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.midnightBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to Tirvona Rides',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<LoginMethod>(
                    key: const Key('login-method'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: LoginMethod.password,
                        icon: Icon(Icons.lock_outline),
                        label: Text('Password'),
                      ),
                      ButtonSegment(
                        value: LoginMethod.whatsappOtp,
                        icon: Icon(Icons.sms_outlined),
                        label: Text('WhatsApp code'),
                      ),
                    ],
                    selected: {method},
                    onSelectionChanged: _submitting
                        ? null
                        : (selection) => _chooseMethod(selection.first),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    textInputAction: withCode
                        ? TextInputAction.done
                        : TextInputAction.next,
                    onFieldSubmitted: withCode ? (_) => _submit() : null,
                    onChanged: (_) {
                      if (_noAccount) setState(() => _noAccount = false);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Mobile number',
                      prefixIcon: Icon(Icons.phone_outlined),
                      hintText: '98XXXXXXXX',
                      border: OutlineInputBorder(),
                    ),
                    validator: validatePhone,
                  ),
                  if (withCode) ...[
                    const SizedBox(height: 12),
                    Text(
                      'We will send a 6-digit code to this number on '
                      'WhatsApp. No password needed.',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Enter your password'
                          : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _submitting ? null : _forgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ErrorBanner(message: _error),
                  if (_noAccount) ...[
                    OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.register),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Create an account'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  LoadingFilledButton(
                    label: withCode ? 'Send code on WhatsApp' : 'Sign in',
                    icon: withCode ? Icons.send_rounded : null,
                    isLoading: _submitting,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 16),
                  // Wraps instead of overflowing with large text sizes.
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('New to Tirvona Rides?'),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => context.push(AppRoutes.register),
                        child: const Text('Create account'),
                      ),
                    ],
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
