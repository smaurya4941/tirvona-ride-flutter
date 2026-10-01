import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/date_field.dart';
import '../../../../shared/widgets/error_banner.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../../shared/widgets/loading_filled_button.dart';
import '../../../rides/presentation/widgets/ride_widgets.dart';
import '../../data/driver_repository.dart';
import '../../domain/driver_models.dart';
import '../data/driver_account_repository.dart';
import '../domain/driver_change.dart';
import 'widgets/change_request_widgets.dart';

/// "Licence number: UP32…" lines for a licence-details request.
List<String> describeProfileChange(DriverChangeRequest request) => [
  for (final entry in request.changes.entries)
    switch (entry.key) {
      'licenseNumber' => 'Licence number: ${entry.value}',
      'licenseExpiry' => 'Licence valid until: ${_day(entry.value)}',
      'dateOfBirth' => 'Date of birth: ${_day(entry.value)}',
      _ => '${entry.key}: ${entry.value}',
    },
];

String _day(Object? value) {
  final date = DateTime.tryParse('$value');
  return date == null ? '$value' : formatDate(date.toUtc());
}

/// An approved driver's licence and personal details. Verified fields are
/// changed through a reviewed request; the address is the driver's own.
class DriverDetailsScreen extends ConsumerStatefulWidget {
  const DriverDetailsScreen({super.key});

  @override
  ConsumerState<DriverDetailsScreen> createState() =>
      _DriverDetailsScreenState();
}

class _DriverDetailsScreenState extends ConsumerState<DriverDetailsScreen> {
  Future<void> _withdraw(DriverChangeRequest request) async {
    try {
      await ref.read(driverAccountRepositoryProvider).withdraw(request.id);
      refreshDriverAccount(ref);
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _requestChange(DriverProfile profile) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LicenceChangeSheet(profile: profile),
    );
    if (sent != true || !mounted) return;
    refreshDriverAccount(ref);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sent for review. We will notify you.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(driverProfileProvider);
    final changes = ref.watch(driverChangesProvider).value;
    final pending = changes?.pendingFor(DriverChangeKind.driverProfile);
    final rejected = changes?.lastRejectedFor(DriverChangeKind.driverProfile);
    return Scaffold(
      appBar: AppBar(title: const Text('Driver details')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LoadErrorView(
          error: error,
          onRetry: () => refreshDriverAccount(ref),
        ),
        data: (profile) => RefreshIndicator(
          onRefresh: () async {
            refreshDriverAccount(ref);
            await ref.read(driverProfileProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (pending != null)
                PendingChangeBanner(
                  request: pending,
                  describe: describeProfileChange,
                  onWithdraw: () => _withdraw(pending),
                ),
              if (rejected != null) RejectedChangeBanner(request: rejected),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Driver code'),
                      subtitle: Text(profile.driverCode),
                      leading: const Icon(Icons.badge_outlined),
                    ),
                    ListTile(
                      title: const Text('Driving licence number'),
                      subtitle: Text(profile.licenseNumber ?? '—'),
                      leading: const Icon(Icons.credit_card_outlined),
                      trailing: const _VerifiedMark(),
                    ),
                    ListTile(
                      title: const Text('Licence valid until'),
                      subtitle: profile.licenseExpiry == null
                          ? const Text('—')
                          : Text(
                              expiryStatus(profile.licenseExpiry!).text,
                              style: TextStyle(
                                color: expiryStatus(profile.licenseExpiry!)
                                    .color,
                              ),
                            ),
                      leading: const Icon(Icons.event_outlined),
                      trailing: const _VerifiedMark(),
                    ),
                    ListTile(
                      title: const Text('Date of birth'),
                      subtitle: Text(
                        profile.dateOfBirth == null
                            ? '—'
                            : formatDate(profile.dateOfBirth!.toUtc()),
                      ),
                      leading: const Icon(Icons.cake_outlined),
                      trailing: const _VerifiedMark(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: OutlinedButton.icon(
                        onPressed: () => _requestChange(profile),
                        icon: const Icon(Icons.edit_note_rounded),
                        label: Text(
                          pending == null
                              ? 'Request a change'
                              : 'Change the request',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _AddressCard(address: profile.address),
              const SizedBox(height: 12),
              const Text(
                'Renewed your licence? Upload the new one under Documents '
                'too, so we can check it.',
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifiedMark extends StatelessWidget {
  const _VerifiedMark();

  @override
  Widget build(BuildContext context) => const Tooltip(
    message: 'Verified by Tirvona',
    child: Icon(Icons.verified_outlined, color: AppColors.success, size: 20),
  );
}

/// The address: saved at once, no review.
class _AddressCard extends ConsumerStatefulWidget {
  const _AddressCard({required this.address});

  final String? address;

  @override
  ConsumerState<_AddressCard> createState() => _AddressCardState();
}

class _AddressCardState extends ConsumerState<_AddressCard> {
  late final _address = TextEditingController(text: widget.address ?? '');
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(driverAccountRepositoryProvider)
          .updateAddress(_address.text.trim());
      ref.invalidate(driverProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Address saved')));
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Home address',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Keep it current. It is saved at once, no review needed.',
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                minLines: 2,
                maxLines: 4,
                maxLength: 240,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'House, street, area, city',
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter your address' : null,
              ),
              ErrorBanner(message: _error),
              LoadingFilledButton(
                label: 'Save address',
                isLoading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Licence number, expiry and date of birth — sent for review.
class _LicenceChangeSheet extends ConsumerStatefulWidget {
  const _LicenceChangeSheet({required this.profile});

  final DriverProfile profile;

  @override
  ConsumerState<_LicenceChangeSheet> createState() =>
      _LicenceChangeSheetState();
}

class _LicenceChangeSheetState extends ConsumerState<_LicenceChangeSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _number = TextEditingController(
    text: widget.profile.licenseNumber ?? '',
  );
  // An expired date cannot seed the picker (it only offers future days).
  late DateTime? _expiry = _futureOrNull(widget.profile.licenseExpiry?.toUtc());
  late DateTime? _dob = widget.profile.dateOfBirth?.toUtc();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  static DateTime? _futureOrNull(DateTime? date) =>
      date != null && date.isAfter(DateTime.now()) ? date : null;

  static bool _sameDay(DateTime? a, DateTime? b) =>
      a?.year == b?.year && a?.month == b?.month && a?.day == b?.day;

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final number = _number.text.replaceAll(RegExp(r'\s'), '').toUpperCase();
    final profile = widget.profile;
    final numberChanged = number != (profile.licenseNumber ?? '');
    final expiryChanged =
        _expiry != null && !_sameDay(_expiry, profile.licenseExpiry?.toUtc());
    final dobChanged =
        _dob != null && !_sameDay(_dob, profile.dateOfBirth?.toUtc());
    if (!numberChanged && !expiryChanged && !dobChanged) {
      setState(() => _error = 'Change at least one detail to send a request.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(driverAccountRepositoryProvider)
          .requestProfileChange(
            licenseNumber: numberChanged ? number : null,
            licenseExpiry: expiryChanged ? _expiry : null,
            dateOfBirth: dobChanged ? _dob : null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Request a change',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'Tirvona checks these against your documents before they '
                'change. You can keep driving meanwhile.',
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _number,
                textCapitalization: TextCapitalization.characters,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Driving licence number',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                validator: (value) {
                  final number = (value ?? '').replaceAll(RegExp(r'\s'), '');
                  return number.length < 4 ? 'Enter your licence number' : null;
                },
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Licence valid until',
                initialValue: _expiry,
                firstDate: today.add(const Duration(days: 1)),
                lastDate: DateTime(today.year + 40),
                onChanged: (value) => setState(() => _expiry = value),
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Date of birth',
                icon: Icons.cake_outlined,
                initialValue: _dob,
                firstDate: DateTime(1900),
                lastDate: DateTime(today.year - 18, today.month, today.day),
                onChanged: (value) => setState(() => _dob = value),
              ),
              const SizedBox(height: 16),
              ErrorBanner(message: _error),
              LoadingFilledButton(
                label: 'Send for review',
                icon: Icons.send_outlined,
                isLoading: _sending,
                onPressed: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
