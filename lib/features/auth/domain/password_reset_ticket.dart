/// Returned by `POST /auth/password/verify-otp` once the reset code was
/// right: a one-time token that lets the user choose a new password.
class PasswordResetTicket {
  const PasswordResetTicket({required this.resetToken, required this.expiresAt});

  /// [receivedAt] anchors the server's relative expiry to this device's
  /// clock (a phone with a wrong clock still counts down correctly).
  factory PasswordResetTicket.fromJson(
    Map<String, dynamic> json, {
    DateTime? receivedAt,
  }) => PasswordResetTicket(
    resetToken: json['resetToken'] as String,
    expiresAt: (receivedAt ?? DateTime.now()).add(
      Duration(seconds: (json['expiresInSeconds'] as num?)?.toInt() ?? 600),
    ),
  );

  final String resetToken;
  final DateTime expiresAt;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);
}
