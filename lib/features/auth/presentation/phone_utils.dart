/// Tirvona Rides launches in India, so a bare 10-digit number is assumed to
/// be +91. Mirrors the API's normalisation (common/phone/phone-number.ts):
/// the server re-normalises and is the authority either way.
String normalizePhone(String input) {
  final compact = input.replaceAll(RegExp(r'[\s\-().]'), '');
  if (RegExp(r'^[6-9]\d{9}$').hasMatch(compact)) return '+91$compact';
  if (RegExp(r'^0[6-9]\d{9}$').hasMatch(compact)) {
    return '+91${compact.substring(1)}';
  }
  if (RegExp(r'^91[6-9]\d{9}$').hasMatch(compact)) return '+$compact';
  if (RegExp(r'^00[1-9]\d{7,14}$').hasMatch(compact)) {
    return '+${compact.substring(2)}';
  }
  // Anything else must already be international (+…); a bare digit string
  // that is not an Indian mobile is left as is and fails validation, like
  // on the server.
  return compact;
}

/// A mobile that can receive the WhatsApp signup code: a 10-digit Indian
/// mobile starting 6–9, or any other E.164 number.
final _mobilePattern = RegExp(r'^(?:\+91[6-9]\d{9}|\+(?!91)[1-9]\d{7,14})$');

String? validatePhone(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return 'Enter your mobile number';
  if (!_mobilePattern.hasMatch(normalizePhone(raw))) {
    return 'Enter a valid 10-digit mobile number';
  }
  return null;
}

/// "+919876543210" → "+91 98765 43210"; other numbers are returned as is.
String formatPhoneForDisplay(String e164) {
  final match = RegExp(r'^\+91(\d{5})(\d{5})$').firstMatch(e164);
  if (match == null) return e164;
  return '+91 ${match.group(1)} ${match.group(2)}';
}
