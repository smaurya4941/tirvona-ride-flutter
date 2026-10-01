import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../data/auth_repository.dart';
import '../domain/otp_challenge.dart';
import '../domain/password_reset_ticket.dart';
import 'session_controller.dart';

/// Where a forgot-password attempt is: the code that was sent, and — once
/// the code was right — the one-time ticket for choosing the new password.
@immutable
class PasswordResetState {
  const PasswordResetState({this.challenge, this.ticket});

  final OtpChallenge? challenge;
  final PasswordResetTicket? ticket;

  String? get phone => challenge?.phone;
}

/// Forgot password, kept between its three screens (number → WhatsApp code
/// → new password). The app relays phone, code and token; NestJS decides
/// whether each is valid.
class PasswordResetFlow extends Notifier<PasswordResetState> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  PasswordResetState build() => const PasswordResetState();

  /// Sends (or keeps) the WhatsApp reset code for [phone].
  Future<OtpChallenge> start(String phone) async {
    final challenge = await _repository.forgotPassword(phone);
    state = PasswordResetState(challenge: challenge);
    return challenge;
  }

  Future<OtpChallenge> resend() async {
    final challenge = await _repository.forgotPassword(_phone);
    state = PasswordResetState(challenge: challenge);
    return challenge;
  }

  /// Checks the code; on success the new-password step may open.
  Future<PasswordResetTicket> verify(String code) async {
    final ticket = await _repository.verifyPasswordResetOtp(
      phone: _phone,
      otp: code,
    );
    state = PasswordResetState(challenge: state.challenge, ticket: ticket);
    return ticket;
  }

  /// Sets the new password and signs this device in (every other device
  /// is signed out by the server). The router then routes by role.
  Future<void> complete(String newPassword) async {
    final ticket = state.ticket;
    if (ticket == null) throw StateError('No verified reset code');
    final session = await _repository.resetPassword(
      resetToken: ticket.resetToken,
      newPassword: newPassword,
      deviceId: await ref.read(secureStorageProvider).readOrCreateDeviceId(),
    );
    await ref.read(sessionControllerProvider.notifier).activate(session);
    state = const PasswordResetState();
  }

  void clear() => state = const PasswordResetState();

  String get _phone {
    final phone = state.phone;
    if (phone == null) throw StateError('No password reset in progress');
    return phone;
  }
}

final passwordResetFlowProvider =
    NotifierProvider<PasswordResetFlow, PasswordResetState>(
      PasswordResetFlow.new,
    );
