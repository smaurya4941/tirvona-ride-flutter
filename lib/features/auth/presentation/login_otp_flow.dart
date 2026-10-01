import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../data/auth_repository.dart';
import '../domain/auth_session.dart';
import '../domain/otp_challenge.dart';
import 'session_controller.dart';

/// The two ways into an existing account. Both end in the same session.
enum LoginMethod {
  password,
  whatsappOtp;

  static LoginMethod? tryParse(String? value) {
    for (final method in values) {
      if (method.name == value) return method;
    }
    return null;
  }
}

/// The sign-in method the user picked last time, so the login screen opens
/// on it. Read once from device storage; a choice made before that read
/// finishes wins over the stored one.
class LoginMethodPreference extends Notifier<LoginMethod> {
  static const _storageKey = 'auth.loginMethod';
  bool _chosen = false;

  @override
  LoginMethod build() {
    unawaited(_load());
    return LoginMethod.password;
  }

  Future<void> _load() async {
    try {
      final stored = LoginMethod.tryParse(
        await ref.read(secureStorageProvider).read(_storageKey),
      );
      if (stored != null && !_chosen) state = stored;
    } catch (_) {
      // Unreadable storage: keep the default.
    }
  }

  Future<void> choose(LoginMethod method) async {
    // Stored even when unchanged on screen: the stored value may still be
    // loading and differ.
    _chosen = true;
    state = method;
    try {
      await ref.read(secureStorageProvider).write(_storageKey, method.name);
    } catch (_) {
      // Only a convenience; the choice still applies to this visit.
    }
  }
}

final loginMethodPreferenceProvider =
    NotifierProvider<LoginMethodPreference, LoginMethod>(
      LoginMethodPreference.new,
    );

/// Login with a WhatsApp code in progress: the challenge the server
/// returned for the number, kept between the login screen and the code
/// screen. `null` means nothing is waiting for a code.
///
/// The app only relays phone + code; NestJS decides whether the number has
/// an account and whether a code is right, expired or used up.
class LoginOtpFlow extends Notifier<OtpChallenge?> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  OtpChallenge? build() => null;

  /// Sends (or keeps, inside the cooldown) the WhatsApp code for [phone].
  Future<OtpChallenge> start(String phone) async {
    final challenge = await _repository.requestLoginOtp(phone);
    state = challenge;
    return challenge;
  }

  /// A new code; every earlier one stops working.
  Future<OtpChallenge> resend() async {
    final challenge = await _repository.requestLoginOtp(_current.phone);
    state = challenge;
    return challenge;
  }

  /// Checks the code. On success the tokens are stored; call
  /// [SessionController.activate] to enter the app.
  Future<AuthSession> verify(String code) async {
    final current = _current;
    final session = await _repository.verifyLoginOtp(
      phone: current.phone,
      otp: code,
      deviceId: await ref.read(secureStorageProvider).readOrCreateDeviceId(),
    );
    await ref.read(sessionControllerProvider.notifier).storeSession(session);
    return session;
  }

  void clear() => state = null;

  OtpChallenge get _current {
    final current = state;
    if (current == null) throw StateError('No WhatsApp login in progress');
    return current;
  }
}

final loginOtpFlowProvider = NotifierProvider<LoginOtpFlow, OtpChallenge?>(
  LoginOtpFlow.new,
);
