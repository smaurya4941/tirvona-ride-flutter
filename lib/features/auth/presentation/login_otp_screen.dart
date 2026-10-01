import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../domain/auth_session.dart';
import 'login_otp_flow.dart';
import 'session_controller.dart';
import 'widgets/otp_verification_panel.dart';

/// Login with a WhatsApp code, step 2: the code. Success signs in; the
/// router then continues by role (customer home, driver screens).
class LoginOtpScreen extends ConsumerStatefulWidget {
  const LoginOtpScreen({super.key});

  @override
  ConsumerState<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

class _LoginOtpScreenState extends ConsumerState<LoginOtpScreen> {
  AuthSession? _session;

  void _backToLogin() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = ref.watch(loginOtpFlowProvider);
    final flow = ref.read(loginOtpFlowProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _backToLogin),
        title: const Text('Sign in'),
      ),
      body: SafeArea(
        child: challenge == null
            ? _NothingToVerify(onStart: _backToLogin)
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: OtpVerificationPanel(
                  challenge: challenge,
                  title: 'Enter your sign-in code',
                  successTitle: 'Signed in',
                  successMessage: 'Taking you to Tirvona Rides…',
                  onChangeNumber: _backToLogin,
                  onResend: flow.resend,
                  onVerify: (code) async => _session = await flow.verify(code),
                  onVerified: () async {
                    final session = _session;
                    if (session == null) return;
                    // The router leaves this screen for the role's home;
                    // clear the finished login only after that.
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

/// Opened without a code on its way (e.g. after a restart).
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
              'There is no sign-in waiting for a code.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onStart,
              child: const Text('Back to sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
