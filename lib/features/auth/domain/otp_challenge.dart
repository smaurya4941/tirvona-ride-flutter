/// What the server says about a verification code it just sent (or kept):
/// returned by `POST /auth/register`, `/auth/resend-otp` and
/// `/auth/phone/send-otp`. It never contains the code — the app neither
/// generates nor checks codes; NestJS decides everything.
class OtpChallenge {
  const OtpChallenge({
    required this.phone,
    required this.maskedPhone,
    required this.codeLength,
    required this.expiresAt,
    required this.resendAvailableAt,
    required this.sendsRemaining,
    required this.codeSent,
    this.verificationId,
  });

  /// [receivedAt] anchors the server's relative timers to this device's
  /// clock, so a phone with a wrong clock still counts down correctly.
  factory OtpChallenge.fromJson(
    Map<String, dynamic> json, {
    DateTime? receivedAt,
  }) {
    final now = receivedAt ?? DateTime.now();
    final expiresIn = (json['expiresInSeconds'] as num?)?.toInt() ?? 300;
    final resendIn = (json['resendAvailableInSeconds'] as num?)?.toInt() ?? 0;
    return OtpChallenge(
      verificationId: json['verificationId'] as String?,
      phone: json['phone'] as String,
      maskedPhone: json['maskedPhone'] as String? ?? json['phone'] as String,
      codeLength: (json['codeLength'] as num?)?.toInt() ?? 6,
      expiresAt: now.add(Duration(seconds: expiresIn)),
      resendAvailableAt: now.add(Duration(seconds: resendIn)),
      sendsRemaining: (json['sendsRemaining'] as num?)?.toInt() ?? 0,
      codeSent: json['codeSent'] as bool? ?? true,
    );
  }

  /// Present for signups only: ties verify/resend to this submission.
  final String? verificationId;
  final String phone;
  final String maskedPhone;
  final int codeLength;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;
  final int sendsRemaining;

  /// False when the server kept a code sent moments ago (form re-submitted
  /// inside the resend cooldown).
  final bool codeSent;

  OtpChallenge withResendAvailableIn(Duration wait) => OtpChallenge(
    verificationId: verificationId,
    phone: phone,
    maskedPhone: maskedPhone,
    codeLength: codeLength,
    expiresAt: expiresAt,
    resendAvailableAt: DateTime.now().add(wait),
    sendsRemaining: sendsRemaining,
    codeSent: codeSent,
  );
}
