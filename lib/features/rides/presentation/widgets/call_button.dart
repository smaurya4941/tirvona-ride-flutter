import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ride_widgets.dart';

/// Opens the phone's dialer with [number] filled in, so one tap on the
/// dialer's call key places the call. Uses the DIAL intent rather than
/// CALL_PHONE, so the app needs no phone permission.
Future<void> callNumber(BuildContext context, String number) async {
  final cleaned = number.replaceAll(RegExp(r'[\s()-]'), '');
  var opened = false;
  try {
    opened = await launchUrl(Uri(scheme: 'tel', path: cleaned));
  } catch (_) {
    // Treated like "no dialer": the message below.
  }
  if (!opened && context.mounted) {
    showErrorSnack(
      context,
      UserFacingError('Could not start a call to $number.'),
    );
  }
}

/// The round "call" button used on the ride screens by both riders and
/// drivers. Shown only while the other person's number is shared.
class CallIconButton extends StatelessWidget {
  const CallIconButton({super.key, required this.phone, required this.name});

  final String phone;
  final String name;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: 'Call $name',
      onPressed: () => callNumber(context, phone),
      icon: const Icon(Icons.call),
    );
  }
}
