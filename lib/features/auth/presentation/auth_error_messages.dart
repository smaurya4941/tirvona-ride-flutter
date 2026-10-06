import '../../../core/network/api_exception.dart';

/// Stable codes the auth API returns (see the API's error-codes.ts).
abstract final class AuthErrorCodes {
  static const otpInvalid = 'OTP_INVALID';
  static const otpExpired = 'OTP_EXPIRED';
  static const otpTooManyAttempts = 'OTP_TOO_MANY_ATTEMPTS';
  static const otpNotActive = 'OTP_NOT_ACTIVE';
  static const otpResendTooSoon = 'OTP_RESEND_TOO_SOON';
  static const otpSendLimitReached = 'OTP_SEND_LIMIT_REACHED';
  static const otpDeliveryFailed = 'OTP_DELIVERY_FAILED';
  static const whatsappRecipientUnavailable = 'WHATSAPP_RECIPIENT_UNAVAILABLE';
  static const phoneAlreadyRegistered = 'PHONE_ALREADY_REGISTERED';
  static const emailAlreadyRegistered = 'EMAIL_ALREADY_REGISTERED';
  static const signupSessionInvalid = 'SIGNUP_SESSION_INVALID';
  static const phoneAlreadyVerified = 'PHONE_ALREADY_VERIFIED';
  // Forgot password / change password.
  static const accountNotFound = 'ACCOUNT_NOT_FOUND';
  static const passwordResetInvalid = 'PASSWORD_RESET_INVALID';
  static const passwordUnchanged = 'PASSWORD_UNCHANGED';
  static const userBlocked = 'USER_BLOCKED';
  static const invalidCredentials = 'AUTH_INVALID_CREDENTIALS';
  static const accountDeletionBlocked = 'ACCOUNT_DELETION_BLOCKED';
  static const accountDeletionPasswordInvalid =
      'ACCOUNT_DELETION_PASSWORD_INVALID';
}

extension AuthApiErrors on ApiException {
  /// `retryAfterSeconds` from a 429 (resend cooldown / send limit).
  Duration? get retryAfter {
    final data = this.data;
    if (data is Map && data['retryAfterSeconds'] is num) {
      return Duration(seconds: (data['retryAfterSeconds'] as num).ceil());
    }
    return null;
  }

  int? get attemptsRemaining {
    final data = this.data;
    if (data is Map && data['attemptsRemaining'] is num) {
      return (data['attemptsRemaining'] as num).toInt();
    }
    return null;
  }

  /// The code has to be replaced before anything else can succeed.
  bool get needsNewCode =>
      code == AuthErrorCodes.otpExpired ||
      code == AuthErrorCodes.otpTooManyAttempts ||
      code == AuthErrorCodes.otpNotActive;

  /// User-facing copy for the signup / OTP screens. Falls back to the
  /// server's own message, which is always safe to show.
  String get authMessage {
    switch (code) {
      case AuthErrorCodes.otpInvalid:
        final left = attemptsRemaining;
        return left == null
            ? "That code isn't right. Check WhatsApp and try again."
            : "That code isn't right. $left ${left == 1 ? 'attempt' : 'attempts'} left.";
      case AuthErrorCodes.otpExpired:
        return 'This code has expired. Request a new one.';
      case AuthErrorCodes.otpTooManyAttempts:
        return 'Too many incorrect attempts. Request a new code.';
      case AuthErrorCodes.otpNotActive:
        return 'This code is no longer active. Use the latest code we sent, '
            'or request a new one.';
      case AuthErrorCodes.otpDeliveryFailed:
        return "We couldn't send the code on WhatsApp right now. "
            'Please try again in a moment.';
      case AuthErrorCodes.whatsappRecipientUnavailable:
        return "We couldn't reach this number on WhatsApp. Make sure WhatsApp "
            'is installed and active on it.';
      case AuthErrorCodes.phoneAlreadyRegistered:
        return 'This mobile number is already registered. Log in instead.';
      case AuthErrorCodes.emailAlreadyRegistered:
        return 'This email is already used by another account.';
      case AuthErrorCodes.signupSessionInvalid:
        return 'This sign-up has expired. Please check your details and '
            'continue again.';
      case AuthErrorCodes.accountNotFound:
        return 'No Tirvona Rides account uses this number. Check the number, '
            'or create an account.';
      case AuthErrorCodes.passwordResetInvalid:
        return 'This reset has expired. Request a new code to continue.';
      case AuthErrorCodes.passwordUnchanged:
        return 'That is your current password. Choose a different one.';
      case AuthErrorCodes.userBlocked:
        return 'This account has been blocked. Please contact Tirvona support.';
    }
    if (statusCode == 429 && code == null) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    return message;
  }
}
