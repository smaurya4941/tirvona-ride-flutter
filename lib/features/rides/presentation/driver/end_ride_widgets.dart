import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/ride_models.dart';

/// Reasons a driver can give for ending a trip without the rider's code. The
/// text is stored on the ride and read by the support team.
const endWithoutCodeReasons = <String>[
  'Rider is not answering',
  'Rider left the vehicle',
  "Rider's phone is off or has no network",
  'Rider refused to share the code',
];

/// "Rider not responding": shown after the driver asked to end the trip. The
/// button unlocks when the server's wait is over ([RideEndOtp.overrideAvailableAt])
/// or at once while an SOS is open. The server enforces the same rule; this
/// only keeps the driver from tapping a button that would be refused.
class RiderNotRespondingCard extends StatefulWidget {
  const RiderNotRespondingCard({
    super.key,
    required this.endOtp,
    required this.busy,
    required this.onEndWithoutCode,
    this.sosOpen = false,
    this.now = DateTime.now,
  });

  final RideEndOtp endOtp;
  final bool busy;

  /// While an SOS is open no wait is asked for.
  final bool sosOpen;

  /// Called with the reason the driver chose.
  final Future<void> Function(String reason) onEndWithoutCode;

  /// The clock, so a test can step through the countdown.
  final DateTime Function() now;

  @override
  State<RiderNotRespondingCard> createState() => _RiderNotRespondingCardState();
}

class _RiderNotRespondingCardState extends State<RiderNotRespondingCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration get _wait =>
      widget.sosOpen ? Duration.zero : widget.endOtp.overrideIn(widget.now());

  Future<void> _confirm() async {
    final reason = await showEndWithoutCodeSheet(context);
    if (reason == null || !mounted) return;
    await widget.onEndWithoutCode(reason);
  }

  @override
  Widget build(BuildContext context) {
    final wait = _wait;
    final ready = wait == Duration.zero;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.person_off_outlined,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Rider not responding?',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.midnightBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              ready
                  ? 'You can end the trip without the code. Tirvona support '
                        'will review it.'
                  : 'If the rider cannot give the code, you can end the trip '
                        'without it in ${_clock(wait)}.',
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            // The theme's filled buttons are full width; this one sits alone.
            OutlinedButton.icon(
              onPressed: ready && !widget.busy ? _confirm : null,
              icon: const Icon(Icons.flag_outlined),
              label: Text(
                ready ? 'End without code' : 'Available in ${_clock(wait)}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// Asks why the trip is ended without the rider's code. Returns the reason
/// text (a preset, plus a note for "Other"), or null when dismissed.
Future<String?> showEndWithoutCodeSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _EndWithoutCodeSheet(),
    );

class _EndWithoutCodeSheet extends StatefulWidget {
  const _EndWithoutCodeSheet();

  @override
  State<_EndWithoutCodeSheet> createState() => _EndWithoutCodeSheetState();
}

class _EndWithoutCodeSheetState extends State<_EndWithoutCodeSheet> {
  static const _other = 'Other';
  final _note = TextEditingController();
  String? _choice;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// What is sent: the preset, or the driver's own words for "Other". The
  /// server needs at least 5 characters.
  String? get _reason {
    final choice = _choice;
    if (choice == null) return null;
    final note = _note.text.trim();
    if (choice == _other) return note.length >= 5 ? note : null;
    return note.isEmpty ? choice : '$choice: $note';
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + viewInsets),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'End the trip without the rider\'s code?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'The fare is already calculated up to the moment you asked to '
                'end the trip. Tell us why, so support can review it.',
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: _choice,
                onChanged: (value) => setState(() => _choice = value),
                child: Column(
                  children: [
                    for (final reason in [...endWithoutCodeReasons, _other])
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: reason,
                        title: Text(reason),
                      ),
                  ],
                ),
              ),
              if (_choice != null) ...[
                const SizedBox(height: 4),
                TextField(
                  controller: _note,
                  maxLength: 200,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _choice == _other
                        ? 'What happened?'
                        : 'Add a note (optional)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _reason == null
                    ? null
                    : () => Navigator.of(context).pop(_reason),
                icon: const Icon(Icons.flag),
                label: const Text('End trip'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Keep waiting'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
