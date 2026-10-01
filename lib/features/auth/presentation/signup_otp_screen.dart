import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../domain/auth_session.dart';
import 'session_controller.dart';
import 'signup_flow.dart';
import 'widgets/otp_verification_panel.dart';

/// Signup step 2: the WhatsApp code. Success creates the account on the
/// server; the router then continues by role (customer home, or driver
/// KYC onboarding — verification is not driver approval).
class SignupOtpScreen extends ConsumerStatefulWidget {
  const SignupOtpScreen({super.key});

  @override
  ConsumerState<SignupOtpScreen> createState() => _SignupOtpScreenState();
}

class _SignupOtpScreenState extends ConsumerState<SignupOtpScreen> {
  AuthSession? _session;

  void _backToForm() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.register);
    }
  }

  Future<void> _sessionInvalid(String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.hourglass_bottom_rounded),
        title: const Text('Sign-up expired'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to sign-up'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    ref.read(signupFlowProvider.notifier).clear();
    _backToForm();
  }

  @override
  Widget build(BuildContext context) {
    final challenge = ref.watch(signupFlowProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _backToForm),
        title: const Text('Verification'),
      ),
      body: SafeArea(
        child: challenge == null || challenge.verificationId == null
            ? _NothingToVerify(onStart: _backToForm)
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: OtpVerificationPanel(
                  challenge: challenge,
                  onChangeNumber: _backToForm,
                  onSessionInvalid: _sessionInvalid,
                  onResend: () =>
                      ref.read(signupFlowProvider.notifier).resend(),
                  onVerify: (code) async {
                    _session = await ref
                        .read(signupFlowProvider.notifier)
                        .verify(code);
                  },
                  onVerified: () async {
                    final session = _session;
                    if (session == null) return;
                    final flow = ref.read(signupFlowProvider.notifier);
                    // The router leaves this screen for the role's home;
                    // clear the finished sign-up only after that.
                    await ref
                        .read(sessionControllerProvider.notifier)
                        .activate(session);
                    flow.clear();
                  },
                ),
              ),
      ),
    );
  }
}

class _NothingToVerify extends StatelessWidget {
  const _NothingToVerify({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phonelink_lock_outlined, size: 48),
            const SizedBox(height: 16),
            const Text(
              'There is no sign-up waiting for a code.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onStart,
              child: const Text('Start sign-up'),
            ),
          ],
        ),
      ),
    );
  }
}
