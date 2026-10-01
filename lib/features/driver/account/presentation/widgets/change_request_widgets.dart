import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../shared/widgets/date_field.dart';
import '../../domain/driver_change.dart';

/// A change waiting for review: what was asked, and a way to take it back.
class PendingChangeBanner extends StatelessWidget {
  const PendingChangeBanner({
    super.key,
    required this.request,
    this.onWithdraw,
    this.describe,
  });

  final DriverChangeRequest request;
  final VoidCallback? onWithdraw;

  /// Turns the requested values into lines ("Licence number: UP32…").
  final List<String> Function(DriverChangeRequest request)? describe;

  @override
  Widget build(BuildContext context) {
    final lines = describe?.call(request) ?? const <String>[];
    return _Banner(
      color: AppColors.warning,
      icon: Icons.hourglass_top_rounded,
      title: 'Update under review · sent ${formatDate(request.submittedAt)}',
      body: [
        ...lines,
        'Your verified details stay active until Tirvona approves this.',
      ],
      action: onWithdraw == null
          ? null
          : TextButton(onPressed: onWithdraw, child: const Text('Withdraw')),
    );
  }
}

/// The last update for this item was not approved, and why.
class RejectedChangeBanner extends StatelessWidget {
  const RejectedChangeBanner({super.key, required this.request});

  final DriverChangeRequest request;

  @override
  Widget build(BuildContext context) {
    return _Banner(
      color: AppColors.error,
      icon: Icons.report_gmailerrorred_rounded,
      title: 'Last update not approved',
      body: [
        if (request.reviewNote != null) request.reviewNote!,
        'Fix the issue and send the update again.',
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final Color color;
  final IconData icon;
  final String title;
  final List<String> body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final line in body)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class ChangeStatusChip extends StatelessWidget {
  const ChangeStatusChip({super.key, required this.status});

  final DriverChangeStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DriverChangeStatus.pending => AppColors.warning,
      DriverChangeStatus.approved => AppColors.success,
      DriverChangeStatus.rejected => AppColors.error,
      DriverChangeStatus.withdrawn => AppColors.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// What the driver chose in [DocumentUploadSheet].
class DocumentUploadChoice {
  const DocumentUploadChoice({
    required this.source,
    this.documentNumber,
    this.expiryDate,
  });

  final ImageSource source;
  final String? documentNumber;
  final DateTime? expiryDate;
}

/// Number, expiry and camera/gallery for a new or renewed document.
class DocumentUploadSheet extends StatefulWidget {
  const DocumentUploadSheet({
    super.key,
    required this.title,
    this.asksForNumber = true,
    this.asksForExpiry = true,
    this.initialNumber,
  });

  final String title;
  final bool asksForNumber;
  final bool asksForExpiry;
  final String? initialNumber;

  @override
  State<DocumentUploadSheet> createState() => _DocumentUploadSheetState();
}

class _DocumentUploadSheetState extends State<DocumentUploadSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _number = TextEditingController(text: widget.initialNumber ?? '');
  DateTime? _expiry;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _pick(ImageSource source) {
    if (!_formKey.currentState!.validate()) return;
    final number = _number.text.trim();
    Navigator.of(context).pop(
      DocumentUploadChoice(
        source: source,
        documentNumber: number.isEmpty ? null : number,
        expiryDate: _expiry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'Take a clear photo of the whole document. Tirvona checks it '
              'before it replaces the one on file.',
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (widget.asksForNumber) ...[
              TextFormField(
                controller: _number,
                textCapitalization: TextCapitalization.characters,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Document number (optional)',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (widget.asksForExpiry) ...[
              DateField(
                label: 'Valid until (optional)',
                icon: Icons.event_available_outlined,
                firstDate: today.add(const Duration(days: 1)),
                lastDate: DateTime(today.year + 30),
                onChanged: (value) => _expiry = value,
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Expired", "Expires in 12 days" or "Valid until 31/03/2027".
({String text, Color color}) expiryStatus(DateTime expiry) {
  final today = DateTime.now();
  final days = DateTime(
    expiry.year,
    expiry.month,
    expiry.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
  if (days < 0) {
    return (text: 'Expired ${formatDate(expiry)}', color: AppColors.error);
  }
  if (days <= 30) {
    return (
      text: days == 0
          ? 'Expires today'
          : 'Expires in $days day${days == 1 ? '' : 's'}',
      color: AppColors.warning,
    );
  }
  return (
    text: 'Valid until ${formatDate(expiry)}',
    color: AppColors.onSurfaceVariant,
  );
}
