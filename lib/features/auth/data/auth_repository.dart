import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../domain/app_user.dart';
import '../domain/auth_session.dart';
import '../domain/otp_challenge.dart';
import '../domain/password_reset_ticket.dart';

class AuthRepository {
  const AuthRepository(this._dio);

  final Dio _dio;

  String get _deviceType {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  /// Starts a signup: the server sends a code to [phone] on WhatsApp. No
  /// account exists until [verifySignupOtp] succeeds.
  Future<OtpChallenge> register({
    required String firstName,
    String? lastName,
    required String phone,
    String? email,
    required String password,
    required UserRole role,
  }) => _challenge(ApiEndpoints.authRegister, {
    'firstName': firstName,
    if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
    'phone': phone,
    if (email != null && email.isNotEmpty) 'email': email,
    'password': password,
    'role': userRoleToJson(role),
  });

  /// Checks the WhatsApp code; on success the account exists and is signed in.
  Future<AuthSession> verifySignupOtp({
    required String phone,
    required String verificationId,
    required String otp,
    required String deviceId,
  }) => _post(ApiEndpoints.authVerifyOtp, {
    'phone': phone,
    'verificationId': verificationId,
    'otp': otp,
    'deviceId': deviceId,
    'deviceType': _deviceType,
  });

  /// A new signup code; every earlier code stops working.
  Future<OtpChallenge> resendSignupOtp({
    required String phone,
    required String verificationId,
  }) => _challenge(ApiEndpoints.authResendOtp, {
    'phone': phone,
    'verificationId': verificationId,
  });

  Future<AuthSession> login({
    required String phone,
    required String password,
    required String deviceId,
  }) => _post(ApiEndpoints.authLogin, {
    'phone': phone,
    'password': password,
    'deviceId': deviceId,
    'deviceType': _deviceType,
  });

  /// Login with a WhatsApp code, step 1: sends a code to [phone] (or keeps
  /// the one sent a moment ago — see [OtpChallenge.codeSent]). Asking again
  /// after the cooldown is the resend.
  Future<OtpChallenge> requestLoginOtp(String phone) =>
      _challenge(ApiEndpoints.authLoginOtpRequest, {'phone': phone});

  /// Login with a WhatsApp code, step 2: the same session as [login].
  Future<AuthSession> verifyLoginOtp({
    required String phone,
    required String otp,
    required String deviceId,
  }) => _post(ApiEndpoints.authLoginOtpVerify, {
    'phone': phone,
    'otp': otp,
    'deviceId': deviceId,
    'deviceType': _deviceType,
  });

  Future<AuthSession> refresh(String refreshToken) =>
      _post(ApiEndpoints.authRefresh, {'refreshToken': refreshToken});

  Future<void> logout(String refreshToken) async {
    try {
      await _dio.post<void>(
        ApiEndpoints.authLogout,
        data: {'refreshToken': refreshToken},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Ends every session of the signed-in user, on every device.
  Future<void> logoutEverywhere() async {
    try {
      await _dio.post<void>(ApiEndpoints.authLogoutAll);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  // ── Forgot password ──────────────────────────────────────────────────

  /// Sends a reset code to [phone] on WhatsApp (or keeps the one sent a
  /// moment ago — see [OtpChallenge.codeSent]).
  Future<OtpChallenge> forgotPassword(String phone) =>
      _challenge(ApiEndpoints.authPasswordForgot, {'phone': phone});

  /// Checks the reset code; the ticket lets the user pick a new password.
  Future<PasswordResetTicket> verifyPasswordResetOtp({
    required String phone,
    required String otp,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.authPasswordVerifyOtp,
        data: {'phone': phone, 'otp': otp},
      );
      return PasswordResetTicket.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Sets the new password. Every other device is signed out; this one is
  /// signed in with the returned session.
  Future<AuthSession> resetPassword({
    required String resetToken,
    required String newPassword,
    required String deviceId,
  }) => _post(ApiEndpoints.authPasswordReset, {
    'resetToken': resetToken,
    'newPassword': newPassword,
    'deviceId': deviceId,
    'deviceType': _deviceType,
  });

  /// Signed-in account created before signup OTP: sends a code to its own
  /// number (the request cannot name another one).
  Future<OtpChallenge> sendPhoneOtp() =>
      _challenge(ApiEndpoints.authPhoneSendOtp, const {});

  Future<AppUser> verifyPhoneOtp(String otp) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.authPhoneVerifyOtp,
        data: {'otp': otp},
      );
      return AppUser.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AppUser> me() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiEndpoints.authMe,
      );
      return AppUser.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<OtpChallenge> _challenge(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: data);
      return OtpChallenge.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AuthSession> _post(String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: data);
      return AuthSession.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(dioProvider)),
);
