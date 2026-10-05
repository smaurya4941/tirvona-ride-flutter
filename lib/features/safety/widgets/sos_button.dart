import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../rides/presentation/widgets/call_button.dart';
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

/// While an alert is open the emergency contacts keep a live view of the
/// ride, and the phone re-sends its position this often so the safety team
/// (and the contacts' location updates) stay current.
const _locationReportInterval = Duration(seconds: 60);

class _SosButtonState extends ConsumerState<SosButton> {
  bool _sending = false;
  bool _reporting = false;
  Timer? _reporter;

  @override
  void dispose() {
    _reporter?.cancel();
    super.dispose();
  }

  /// Sends the phone's newer position for as long as the alert is open and
  /// this ride screen is on. It never starts a second alert: it checks the
  /// first one is still open before posting.
  void _startReporting(String alertId) {
    _reporter?.cancel();
    _reporter = Timer.periodic(
      _locationReportInterval,
      (_) => _reportLocation(alertId),
    );
  }

  Future<void> _reportLocation(String alertId) async {
    if (_reporting || !mounted) return;
    _reporting = true;
    try {
      final repository = ref.read(safetyRepositoryProvider);
      final alerts = await repository.sosForRide(widget.rideId);
      final current = alerts.where((alert) => alert.id == alertId).firstOrNull;
      if (current == null || !current.status.isOpen) {
        _reporter?.cancel();
        return;
      }
      final fix = await _currentFix(askPermission: false);
      if (fix == null || !mounted) return;
      await repository.triggerSos(widget.rideId, fix: fix);
    } on ApiException {
      // Closed, or the ride ended: nothing more to report.
      _reporter?.cancel();
    } catch (_) {
      // Offline or no GPS right now: the next tick tries again.
    } finally {
      _reporting = false;
    }
  }

  Future<void> _onPressed() async {
    unawaited(HapticFeedback.heavyImpact());
    // Never holds the alert back: no answer within a second means "unknown".
    final hasContacts = await ref
        .read(emergencyContactsProvider.future)
        .then<bool?>((contacts) => contacts.isNotEmpty)
        .timeout(const Duration(seconds: 1), onTimeout: () => null)
        .catchError((Object _) => null);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmSosDialog(hasContacts: hasContacts),
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
      _startReporting(alert.id);
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
  Future<SosFix?> _currentFix({bool askPermission = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && askPermission) {
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
  const _ConfirmSosDialog({required this.hasContacts});

  /// null: not known yet (the alert is never held back for it).
  final bool? hasContacts;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.sos, color: _sosRed, size: 40),
      title: const Text('Trigger emergency alert?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The Tirvona safety team will be alerted right away with your '
            'ride details and current location.',
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.chat_outlined, size: 18, color: _sosRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasContacts == false
                      ? 'You have no emergency contacts yet. Add some in '
                            'Profile → Emergency contacts so we can also '
                            'send them your live location on WhatsApp.'
                      : 'Your emergency contacts will also get your live '
                            'location on WhatsApp.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ],
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

/// After an alert: its reference and live status, whether the emergency
/// contacts were messaged on WhatsApp, and one-tap calls to 112 and to the
/// contacts (a call is always the backup if a message did not get through).
class SosActiveSheet extends ConsumerStatefulWidget {
  const SosActiveSheet({
    super.key,
    required this.rideId,
    required this.initial,
  });

  final String rideId;
  final SosAlert initial;

  @override
  ConsumerState<SosActiveSheet> createState() => _SosActiveSheetState();
}

class _SosActiveSheetState extends ConsumerState<SosActiveSheet> {
  Timer? _poll;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    // The WhatsApp messages go out in the background right after the alert:
    // look again every few seconds until each contact has an answer.
    _poll = Timer.periodic(const Duration(seconds: 3), (timer) {
      _polls++;
      final alert = _latest();
      if (_polls > 12 || (alert != null && !alert.contactsStillSending)) {
        timer.cancel();
        return;
      }
      ref.invalidate(rideSosProvider(widget.rideId));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  SosAlert? _latest() => ref
      .read(rideSosProvider(widget.rideId))
      .value
      ?.where((alert) => alert.id == widget.initial.id)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final rideId = widget.rideId;
    final latest = ref
        .watch(rideSosProvider(rideId))
        .value
        ?.where((alert) => alert.id == widget.initial.id)
        .firstOrNull;
    final alert = latest ?? widget.initial;
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
            if (alert.contacts.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ContactsAlerted(contacts: alert.contacts),
            ],
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

/// Who got the WhatsApp alert with the live location, and who did not.
class _ContactsAlerted extends StatelessWidget {
  const _ContactsAlerted({required this.contacts});

  final List<SosContactStatus> contacts;

  @override
  Widget build(BuildContext context) {
    final failed = contacts.any((c) => c.state == SosContactState.failed);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.chat_outlined, size: 18, color: AppColors.success),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Live location sent on WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final contact in contacts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  switch (contact.state) {
                    SosContactState.sent => const Icon(
                      Icons.check_circle,
                      size: 18,
                      color: AppColors.success,
                    ),
                    SosContactState.failed => const Icon(
                      Icons.error_outline,
                      size: 18,
                      color: _sosRed,
                    ),
                    SosContactState.pending => const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  },
                  const SizedBox(width: 10),
                  Expanded(child: Text(contact.name)),
                  Text(
                    switch (contact.state) {
                      SosContactState.sent => 'Sent',
                      SosContactState.failed => "Couldn't send. Call them",
                      SosContactState.pending => 'Sending…',
                    },
                    style: TextStyle(
                      fontSize: 12,
                      color: contact.state == SosContactState.failed
                          ? _sosRed
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (failed)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'The safety team can see this too and will try to reach them.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
