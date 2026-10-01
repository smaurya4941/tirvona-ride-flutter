import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/error_banner.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../../shared/widgets/loading_filled_button.dart';
import '../../../rides/presentation/widgets/ride_widgets.dart';
import '../../data/vehicle_repository.dart';
import '../../domain/driver_models.dart';
import '../data/driver_account_repository.dart';
import '../domain/driver_change.dart';
import 'widgets/change_request_widgets.dart';

const _fieldLabels = {
  'vehicleType': 'Type',
  'registrationNumber': 'Registration',
  'make': 'Make',
  'model': 'Model',
  'color': 'Colour',
  'manufactureYear': 'Year',
};

List<String> describeVehicleChange(DriverChangeRequest request) => [
  for (final entry in request.changes.entries)
    '${_fieldLabels[entry.key] ?? entry.key}: ${entry.key == 'vehicleType' ? VehicleType.fromWire('${entry.value}').label : entry.value}',
];

/// The approved driver's vehicle as verified, and a reviewed way to change it.
class DriverVehicleScreen extends ConsumerWidget {
  const DriverVehicleScreen({super.key});

  Future<void> _withdraw(
    BuildContext context,
    WidgetRef ref,
    DriverChangeRequest request,
  ) async {
    try {
      await ref.read(driverAccountRepositoryProvider).withdraw(request.id);
      refreshDriverAccount(ref);
    } on Object catch (error) {
      if (context.mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _requestChange(
    BuildContext context,
    WidgetRef ref,
    Vehicle vehicle,
  ) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VehicleChangeSheet(vehicle: vehicle),
    );
    if (sent != true || !context.mounted) return;
    refreshDriverAccount(ref);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sent for review. We will notify you.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = ref.watch(myVehiclesProvider);
    final changes = ref.watch(driverChangesProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle')),
      body: vehicles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LoadErrorView(
          error: error,
          onRetry: () => ref.invalidate(myVehiclesProvider),
        ),
        data: (vehicles) {
          final active = vehicles.where((vehicle) => vehicle.isActive).toList();
          if (active.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No active vehicle on your account. Contact Tirvona support.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(myVehiclesProvider)
                ..invalidate(driverChangesProvider);
              await ref.read(myVehiclesProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                for (final vehicle in active) ...[
                  if (changes?.pendingFor(
                        DriverChangeKind.vehicle,
                        vehicleId: vehicle.id,
                      )
                      case final pending?)
                    PendingChangeBanner(
                      request: pending,
                      describe: describeVehicleChange,
                      onWithdraw: () => _withdraw(context, ref, pending),
                    ),
                  if (changes?.lastRejectedFor(
                        DriverChangeKind.vehicle,
                        vehicleId: vehicle.id,
                      )
                      case final rejected?)
                    RejectedChangeBanner(request: rejected),
                  _VehicleCard(
                    vehicle: vehicle,
                    onRequestChange: () =>
                        _requestChange(context, ref, vehicle),
                    hasPending:
                        changes?.pendingFor(
                          DriverChangeKind.vehicle,
                          vehicleId: vehicle.id,
                        ) !=
                        null,
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_copy_outlined),
                    title: const Text('Vehicle documents'),
                    subtitle: const Text('RC, insurance, permit, PUC'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.driverDocuments),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Changed your vehicle or its registration? Request the change '
                  'here and upload the new RC under Documents.',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.onRequestChange,
    required this.hasPending,
  });

  final Vehicle vehicle;
  final VoidCallback onRequestChange;
  final bool hasPending;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String?)>[
      ('Type', vehicle.vehicleType.label),
      ('Registration', vehicle.registrationNumber),
      ('Make', vehicle.make),
      ('Model', vehicle.model),
      ('Colour', vehicle.color),
      ('Year', vehicle.manufactureYear?.toString()),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.local_taxi_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    vehicle.title.isEmpty
                        ? vehicle.vehicleType.label
                        : vehicle.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Tooltip(
                  message: 'Verified by Tirvona',
                  child: Icon(
                    Icons.verified_outlined,
                    color: AppColors.success,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value == null || value.isEmpty ? '—' : value,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRequestChange,
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(
                hasPending ? 'Change the request' : 'Request a change',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleChangeSheet extends ConsumerStatefulWidget {
  const _VehicleChangeSheet({required this.vehicle});

  final Vehicle vehicle;

  @override
  ConsumerState<_VehicleChangeSheet> createState() =>
      _VehicleChangeSheetState();
}

class _VehicleChangeSheetState extends ConsumerState<_VehicleChangeSheet> {
  final _formKey = GlobalKey<FormState>();
  late VehicleType _type = widget.vehicle.vehicleType;
  late final _plate = TextEditingController(
    text: widget.vehicle.registrationNumber,
  );
  late final _make = TextEditingController(text: widget.vehicle.make ?? '');
  late final _model = TextEditingController(text: widget.vehicle.model ?? '');
  late final _color = TextEditingController(text: widget.vehicle.color ?? '');
  late final _year = TextEditingController(
    text: widget.vehicle.manufactureYear?.toString() ?? '',
  );
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_plate, _make, _model, _color, _year]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Only what differs from the verified vehicle (null = unchanged).
  String? _changed(TextEditingController controller, String? current) {
    final value = controller.text.trim();
    return value.isEmpty || value == (current ?? '') ? null : value;
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final vehicle = widget.vehicle;
    final plate = _plate.text.replaceAll(RegExp(r'\s'), '').toUpperCase();
    final year = int.tryParse(_year.text.trim());
    final change = VehicleChange(
      vehicleType: _type != vehicle.vehicleType ? _type : null,
      registrationNumber: plate != vehicle.registrationNumber ? plate : null,
      make: _changed(_make, vehicle.make),
      model: _changed(_model, vehicle.model),
      color: _changed(_color, vehicle.color),
      manufactureYear: year != vehicle.manufactureYear ? year : null,
    );
    if (change.toJson().isEmpty) {
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
          .requestVehicleChange(vehicle.id, change);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    border: const OutlineInputBorder(),
    counterText: '',
  );

  @override
  Widget build(BuildContext context) {
    final maxYear = DateTime.now().year + 1;
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
                'Request a vehicle change',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'Riders see these details, so Tirvona checks them first. '
                'Your verified vehicle stays active meanwhile.',
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<VehicleType>(
                initialValue: _type,
                decoration: _decoration('Vehicle type'),
                items: [
                  for (final type in VehicleType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (value) => setState(() => _type = value ?? _type),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                maxLength: 15,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9 ]')),
                ],
                decoration: _decoration('Registration number'),
                validator: (value) {
                  final plate = (value ?? '').replaceAll(RegExp(r'\s'), '');
                  return plate.length < 4 || plate.length > 15
                      ? 'Enter the registration number'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _make,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                      decoration: _decoration('Make'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _model,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                      decoration: _decoration('Model'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _color,
                      maxLength: 40,
                      textCapitalization: TextCapitalization.words,
                      decoration: _decoration('Colour'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _year,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _decoration('Year'),
                      validator: (value) {
                        if ((value ?? '').isEmpty) return null;
                        final year = int.tryParse(value!);
                        return year == null || year < 1980 || year > maxYear
                            ? '1980–$maxYear'
                            : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
