import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/error_banner.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';
import '../domain/otp_challenge.dart';
import 'auth_error_messages.dart';
import 'session_controller.dart';
import 'widgets/otp_verification_panel.dart';

/// Phone verification for signed-in accounts created before signup OTP
/// (new accounts are verified during signup and never land here). The
/// code goes to the account's own number on WhatsApp; once verified the
/// router moves on to the role's shell.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  OtpChallenge? _challenge;
  AppUser? _verifiedUser;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final challenge = await ref.read(authRepositoryProvider).sendPhoneOtp();
      if (mounted) setState(() => _challenge = challenge);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == AuthErrorCodes.phoneAlreadyVerified) {
        await ref.read(sessionControllerProvider.notifier).refreshUser();
        return;
      }
      setState(() => _error = error.authMessage);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = _challenge;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify your number'),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).logout(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: challenge == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _sending
                      ? const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Sending a code on WhatsApp…'),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ErrorBanner(message: _error),
                            FilledButton(
                              onPressed: _send,
                              child: const Text('Send code on WhatsApp'),
                            ),
                          ],
                        ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: OtpVerificationPanel(
                  challenge: challenge,
                  onResend: () =>
                      ref.read(authRepositoryProvider).sendPhoneOtp(),
                  onVerify: (code) async {
                    _verifiedUser = await ref
                        .read(authRepositoryProvider)
                        .verifyPhoneOtp(code);
                  },
                  onVerified: () async {
                    final user = _verifiedUser;
                    if (user != null) {
                      ref
                          .read(sessionControllerProvider.notifier)
                          .updateUser(user);
                    }
                  },
                ),
              ),
      ),
    );
  }
}
