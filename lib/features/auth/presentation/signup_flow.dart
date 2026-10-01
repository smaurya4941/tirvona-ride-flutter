import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';
import '../domain/auth_session.dart';
import '../domain/otp_challenge.dart';
import 'session_controller.dart';

/// The sign-up in progress: the challenge the server returned for the
/// submitted form, kept between the signup form and the OTP screen.
/// `null` means there is nothing to verify (start from the form).
///
/// The app only relays phone + code (+ the server's verificationId);
/// whether a code is right, expired or used up is decided by NestJS.
class SignupFlow extends Notifier<OtpChallenge?> {
  @override
  OtpChallenge? build() => null;

  /// Submits the form. The server sends the WhatsApp code; no account
  /// exists yet.
  Future<OtpChallenge> start({
    required String firstName,
    String? lastName,
    required String phone,
    String? email,
    required String password,
    required UserRole role,
  }) async {
    final challenge = await ref
        .read(authRepositoryProvider)
        .register(
          firstName: firstName,
          lastName: lastName,
          phone: phone,
          email: email,
          password: password,
          role: role,
        );
    state = challenge;
    return challenge;
  }

  Future<OtpChallenge> resend() async {
    final current = _current;
    final challenge = await ref
        .read(authRepositoryProvider)
        .resendSignupOtp(
          phone: current.phone,
          verificationId: current.verificationId!,
        );
    state = challenge;
    return challenge;
  }

  /// Verifies the code. On success the account exists and its tokens are
  /// stored; call [SessionController.activate] to enter the app.
  Future<AuthSession> verify(String code) async {
    final current = _current;
    final storage = ref.read(secureStorageProvider);
    final session = await ref
        .read(authRepositoryProvider)
        .verifySignupOtp(
          phone: current.phone,
          verificationId: current.verificationId!,
          otp: code,
          deviceId: await storage.readOrCreateDeviceId(),
        );
    await ref.read(sessionControllerProvider.notifier).storeSession(session);
    return session;
  }

  void clear() => state = null;

  OtpChallenge get _current {
    final current = state;
    if (current == null || current.verificationId == null) {
      throw StateError('No sign-up in progress');
    }
    return current;
  }
}

final signupFlowProvider = NotifierProvider<SignupFlow, OtpChallenge?>(
  SignupFlow.new,
);
