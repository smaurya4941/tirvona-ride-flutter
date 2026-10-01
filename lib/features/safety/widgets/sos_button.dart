import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';
import '../models/safety_models.dart';
import '../repository/safety_repository.dart';

const _sosRed = Color(0xFFDC2626);

/// Emergency number for India (police, fire, ambulance).
const emergencyNumber = '112';

/// A clearly visible SOS control for the active-ride screens (customer and
/// driver). Tap → one confirmation → the alert is raised with the phone's
/// current position. The server decides whether SOS is allowed for this
/// ride; the button only asks.
class SosButton extends ConsumerStatefulWidget {
  const SosButton({super.key, required this.rideId, this.compact = false});

  final String rideId;

  /// Round icon button for app bars / map overlays.
  final bool compact;

  @override
  ConsumerState<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<SosButton> {
  bool _sending = false;

  Future<void> _onPressed() async {
    unawaited(HapticFeedback.heavyImpact());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _ConfirmSosDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final fix = await _currentFix();
      final alert = await ref
          .read(safetyRepositoryProvider)
          .triggerSos(widget.rideId, fix: fix);
      unawaited(HapticFeedback.heavyImpact());
      ref.invalidate(rideSosProvider(widget.rideId));
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) =>
            SosActiveSheet(rideId: widget.rideId, initial: alert),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      // Whatever happened, the emergency number always works.
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Alert not sent'),
          content: Text(
            '${error.message}\n\nIf you are in danger, call $emergencyNumber now.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _sosRed),
              onPressed: () => callNumber(context, emergencyNumber),
              icon: const Icon(Icons.call),
              label: const Text('Call $emergencyNumber'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// A quick fix; never holds the alert back for long. Without one the
  /// server uses the driver's last known position.
  Future<SosFix?> _currentFix() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );
      } on TimeoutException {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) return null;
      return SosFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    const spinner = SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
    if (widget.compact) {
      return Semantics(
        button: true,
        label: 'SOS emergency alert',
        child: IconButton.filled(
          tooltip: 'SOS',
          style: IconButton.styleFrom(
            backgroundColor: _sosRed,
            foregroundColor: Colors.white,
          ),
          onPressed: _sending ? null : _onPressed,
          icon: _sending ? spinner : const Icon(Icons.sos),
        ),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _sosRed,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
      ),
      onPressed: _sending ? null : _onPressed,
      icon: _sending ? spinner : const Icon(Icons.sos),
      label: Text(_sending ? 'Sending alert…' : 'SOS'),
    );
  }
}

class _ConfirmSosDialog extends StatelessWidget {
  const _ConfirmSosDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.sos, color: _sosRed, size: 40),
      title: const Text('Trigger emergency alert?'),
      content: const Text(
        'The Tirvona safety team will be alerted right away with your ride '
        'details and current location.',
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: 8,
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _sosRed,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Send emergency alert'),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}

/// After an alert: its reference and live status, one-tap calls to 112 and
/// to the user's emergency contacts. (Tirvona does not message contacts
/// automatically yet, so the app makes calling them easy instead.)
class SosActiveSheet extends ConsumerWidget {
  const SosActiveSheet({
    super.key,
    required this.rideId,
    required this.initial,
  });

  final String rideId;
  final SosAlert initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref
        .watch(rideSosProvider(rideId))
        .value
        ?.where((alert) => alert.id == initial.id)
        .firstOrNull;
    final alert = latest ?? initial;
    final contacts = ref.watch(emergencyContactsProvider).value ?? const [];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CircleAvatar(
              radius: 30,
              backgroundColor: Color(0xFFFEE2E2),
              child: Icon(Icons.sos, color: _sosRed, size: 32),
            ),
            const SizedBox(height: 12),
            const Text(
              'Emergency alert sent',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Reference ${alert.sosCode}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: alert.status.isOpen
                    ? const Color(0xFFFFF7ED)
                    : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    alert.status.isOpen
                        ? Icons.support_agent
                        : Icons.check_circle,
                    color: alert.status.isOpen
                        ? AppColors.bhagwa
                        : AppColors.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(alert.status.label)),
                  IconButton(
                    tooltip: 'Refresh status',
                    onPressed: () => ref.invalidate(rideSosProvider(rideId)),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _sosRed,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => callNumber(context, emergencyNumber),
              icon: const Icon(Icons.call),
              label: const Text('Call $emergencyNumber (Emergency)'),
            ),
            if (contacts.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Call an emergency contact',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final contact in contacts.take(3))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(contact.name),
                  subtitle: Text(
                    [
                      contact.relationship,
                      contact.phone,
                    ].whereType<String>().join(' · '),
                  ),
                  trailing: IconButton.filledTonal(
                    tooltip: 'Call ${contact.name}',
                    onPressed: () => callNumber(context, contact.phone),
                    icon: const Icon(Icons.call),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to ride'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> callNumber(BuildContext context, String number) async {
  final opened = await launchUrl(Uri(scheme: 'tel', path: number));
  if (!opened && context.mounted) {
    showErrorSnack(
      context,
      UserFacingError('Could not start a call to $number.'),
    );
  }
}
