import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/ride_repository.dart';
import '../../domain/cancellation_models.dart';
import '../../domain/ride_formatters.dart';
import '../../domain/ride_models.dart';
import 'ride_widgets.dart';

/// Shows the cancel sheet for [ride] and cancels it if the user confirms.
/// Returns the cancelled ride, or null if the user backed out.
///
/// The reasons and any cancellation fee come from the server
/// (`GET /rides/:id/cancellation`); the app never decides either.
Future<Ride?> showCancelRideSheet(
  BuildContext context, {
  required Ride ride,
  required bool asDriver,
}) {
  return showModalBottomSheet<Ride>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: CancelRideSheet(ride: ride, asDriver: asDriver),
    ),
  );
}

class CancelRideSheet extends ConsumerStatefulWidget {
  const CancelRideSheet({
    super.key,
    required this.ride,
    required this.asDriver,
  });

  final Ride ride;
  final bool asDriver;

  @override
  ConsumerState<CancelRideSheet> createState() => _CancelRideSheetState();
}

class _CancelRideSheetState extends ConsumerState<CancelRideSheet> {
  late Future<CancellationPreview> _preview;
  final _note = TextEditingController();
  String? _reasonCode;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _preview = ref
        .read(rideRepositoryProvider)
        .cancellationPreview(widget.ride.id);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(CancellationReasonOption reason) async {
    if (reason.requiresNote && _note.text.trim().length < 3) {
      setState(() => _error = 'Please tell us briefly why you are cancelling.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final cancelled = await ref
          .read(rideRepositoryProvider)
          .cancel(
            widget.ride.id,
            reasonCode: reason.code,
            note: reason.requiresNote ? _note.text : null,
          );
      if (mounted) Navigator.of(context).pop(cancelled);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = errorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<CancellationPreview>(
        future: _preview,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.error_outline,
              text: errorMessage(snapshot.error!),
              action: TextButton(
                onPressed: () => setState(
                  () => _preview = ref
                      .read(rideRepositoryProvider)
                      .cancellationPreview(widget.ride.id),
                ),
                child: const Text('Try again'),
              ),
            );
          }
          final preview = snapshot.data!;
          if (!preview.cancellable) {
            return const _Message(
              icon: Icons.block,
              text: 'This ride can no longer be cancelled.',
            );
          }
          final reasons = preview.reasons;
          final selected = reasons
              .where((reason) => reason.code == _reasonCode)
              .firstOrNull;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.asDriver
                      ? 'Why are you cancelling?'
                      : 'Why do you want to cancel?',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _FeeBanner(fee: preview.fee),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: _reasonCode,
                  onChanged: (value) => setState(() {
                    _reasonCode = value;
                    _error = null;
                  }),
                  child: Column(
                    children: [
                      for (final reason in reasons)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: reason.code,
                          title: Text(reason.label),
                        ),
                    ],
                  ),
                ),
                if (selected?.requiresNote ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: TextField(
                      controller: _note,
                      maxLength: 240,
                      maxLines: 2,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Tell us briefly',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: selected == null || _submitting
                      ? null
                      : () => _submit(selected),
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          preview.fee.applies
                              ? 'Cancel and pay ${RideFormat.money(preview.fee.amount)} fee'
                              : 'Cancel ride',
                        ),
                ),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(
                    widget.asDriver ? 'Keep the ride' : 'Keep my ride',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FeeBanner extends StatelessWidget {
  const _FeeBanner({required this.fee});

  final CancellationFee fee;

  @override
  Widget build(BuildContext context) {
    final charged = fee.applies;
    final until = fee.freeUntil;
    final text = !charged && until != null
        ? 'Free cancellation until ${TimeOfDay.fromDateTime(until).format(context)}'
        : fee.explanation;
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: charged
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.surfaceSand,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            charged ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: charged ? AppColors.error : AppColors.success,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    );
  }
}
