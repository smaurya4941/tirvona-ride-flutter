import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../shared/widgets/loading_filled_button.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/driver_repository.dart';
import '../domain/driver_models.dart';
import 'widgets/onboarding_steps.dart';

/// Onboarding step 1: licence and personal details (PATCH /drivers/me).
class DriverRegistrationScreen extends ConsumerWidget {
  const DriverRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(driverProfileProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver details'),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).logout(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => LoadErrorView(
            error: error,
            onRetry: () => ref.invalidate(driverProfileProvider),
          ),
          data: (profile) => _ProfileForm(profile: profile),
        ),
      ),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});

  final DriverProfile profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final _licenseNumber = TextEditingController(
    text: widget.profile.licenseNumber,
  );
  late final _address = TextEditingController(text: widget.profile.address);
  late DateTime? _licenseExpiry = widget.profile.licenseExpiry;
  late DateTime? _dateOfBirth = widget.profile.dateOfBirth;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _licenseNumber.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(driverRepositoryProvider)
          .updateProfile(
            licenseNumber: _licenseNumber.text.trim().toUpperCase(),
            licenseExpiry: _licenseExpiry!,
            dateOfBirth: _dateOfBirth,
            address: _address.text.trim(),
          );
      ref.invalidate(driverProfileProvider);
      if (mounted) unawaited(context.push(AppRoutes.driverVehicle));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const OnboardingSteps(current: 0),
          const SizedBox(height: 28),
          if (widget.profile.rejectionReason != null) ...[
            ErrorBanner(
              message:
                  'Previous submission was rejected: ${widget.profile.rejectionReason}',
            ),
          ],
          TextFormField(
            controller: _licenseNumber,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Driving licence number',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final length = value?.trim().length ?? 0;
              return (length < 4 || length > 30)
                  ? 'Enter a valid licence number'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Licence expiry date',
            initialValue: _licenseExpiry,
            firstDate: now,
            lastDate: DateTime(now.year + 30),
            onChanged: (value) => _licenseExpiry = value,
            validator: (value) =>
                value == null ? 'Select the licence expiry date' : null,
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Date of birth',
            icon: Icons.cake_outlined,
            initialValue: _dateOfBirth,
            firstDate: DateTime(now.year - 80),
            lastDate: DateTime(now.year - 18, now.month, now.day),
            onChanged: (value) => _dateOfBirth = value,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _address,
            minLines: 2,
            maxLines: 4,
            maxLength: 240,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Address',
              prefixIcon: Icon(Icons.home_outlined),
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
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
