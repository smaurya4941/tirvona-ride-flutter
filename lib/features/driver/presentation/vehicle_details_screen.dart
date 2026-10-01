import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../shared/widgets/loading_filled_button.dart';
import '../data/vehicle_repository.dart';
import '../domain/driver_models.dart';
import 'widgets/onboarding_steps.dart';

/// Onboarding step 2: the driver's vehicle. Creates it on first visit and
/// updates the existing active vehicle on later visits (e.g. after a
/// rejection), so re-running onboarding never creates duplicates.
class VehicleDetailsScreen extends ConsumerWidget {
  const VehicleDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = ref.watch(myVehiclesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle details')),
      body: SafeArea(
        child: vehicles.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => LoadErrorView(
            error: error,
            onRetry: () => ref.invalidate(myVehiclesProvider),
          ),
          data: (vehicles) => _VehicleForm(
            existing: vehicles.where((vehicle) => vehicle.isActive).firstOrNull,
          ),
        ),
      ),
    );
  }
}

class _VehicleForm extends ConsumerStatefulWidget {
  const _VehicleForm({required this.existing});

  final Vehicle? existing;

  @override
  ConsumerState<_VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends ConsumerState<_VehicleForm> {
  final _formKey = GlobalKey<FormState>();
  late VehicleType _type = widget.existing?.vehicleType ?? VehicleType.bike;
  late final _registration = TextEditingController(
    text: widget.existing?.registrationNumber,
  );
  late final _make = TextEditingController(text: widget.existing?.make);
  late final _model = TextEditingController(text: widget.existing?.model);
  late final _color = TextEditingController(text: widget.existing?.color);
  late final _year = TextEditingController(
    text: widget.existing?.manufactureYear?.toString(),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_registration, _make, _model, _color, _year]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = ref.read(vehicleRepositoryProvider);
    final year = int.tryParse(_year.text.trim());
    try {
      final existing = widget.existing;
      if (existing == null) {
        await repository.create(
          vehicleType: _type,
          registrationNumber: _registration.text,
          make: _make.text.trim(),
          model: _model.text.trim(),
          color: _color.text.trim(),
          manufactureYear: year,
        );
      } else {
        await repository.update(
          existing.id,
          vehicleType: _type,
          registrationNumber: _registration.text,
          make: _make.text.trim(),
          model: _model.text.trim(),
          color: _color.text.trim(),
          manufactureYear: year,
        );
      }
      ref.invalidate(myVehiclesProvider);
      if (mounted) unawaited(context.push(AppRoutes.driverKyc));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxYear = DateTime.now().year + 1;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const OnboardingSteps(current: 1),
          const SizedBox(height: 28),
          Text('Vehicle type', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          // Chips wrap on narrow phones; four segments would not fit.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in VehicleType.values)
                ChoiceChip(
                  avatar: Icon(switch (type) {
                    VehicleType.bike => Icons.two_wheeler,
                    VehicleType.auto ||
                    VehicleType.eRickshaw => Icons.electric_rickshaw,
                    VehicleType.cab => Icons.directions_car,
                  }, size: 18),
                  label: Text(type.label),
                  selected: _type == type,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _type = type),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _registration,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9 ]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Registration number',
              hintText: 'UP32AB1234',
              prefixIcon: Icon(Icons.pin_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final length = value?.replaceAll(' ', '').length ?? 0;
              return (length < 4 || length > 15)
                  ? 'Enter a valid registration number'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _make,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Make',
                    hintText: 'Honda',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _model,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    hintText: 'Shine',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _color,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Colour',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Year',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    final year = int.tryParse(value);
                    return (year == null || year < 1980 || year > maxYear)
                        ? '1980–$maxYear'
                        : null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ErrorBanner(message: _error),
          LoadingFilledButton(
            label: 'Save & continue',
            isLoading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
