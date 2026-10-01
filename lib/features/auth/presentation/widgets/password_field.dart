import 'package:flutter/material.dart';

/// The API's password policy (common/validation/password.ts): at least 8
/// characters with a lowercase and an uppercase letter, a digit and a symbol.
/// The server re-checks; this only gives instant feedback.
final strongPasswordPattern = RegExp(
  r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^\da-zA-Z]).{8,}$',
);

const passwordRequirements =
    'At least 8 characters with upper & lower case, a number and a symbol';

String? validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Enter a password';
  if (password.length > 128) return 'Use at most 128 characters';
  return strongPasswordPattern.hasMatch(password)
      ? null
      : 'Password does not meet the requirements';
}

/// A password input with a show/hide toggle, used by sign-in, sign-up,
/// change password and reset password.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.helperText,
    this.validator,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.isNewPassword = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final FormFieldValidator<String>? validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  /// Offers the platform's "suggest a strong password" instead of autofill.
  final bool isNewPassword;
  final bool enabled;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscure,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: widget.textInputAction,
      autofillHints: [
        widget.isNewPassword
            ? AutofillHints.newPassword
            : AutofillHints.password,
      ],
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline),
        helperText: widget.helperText,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator: widget.validator,
    );
  }
}
