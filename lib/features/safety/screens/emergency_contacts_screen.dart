import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../shared/widgets/loading_filled_button.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';
import '../models/safety_models.dart';
import '../repository/safety_repository.dart';
import '../widgets/sos_button.dart';

/// Profile → Emergency contacts. The people the safety team can reach if
/// this user raises an SOS. One is primary; the server enforces the limit,
/// valid numbers and ownership.
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  static const maxContacts = 5;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    EmergencyContact? contact,
  ]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ContactForm(contact: contact),
    );
    if (saved == true) ref.invalidate(emergencyContactsProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    EmergencyContact contact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${contact.name}?'),
        content: Text(
          contact.isPrimary
              ? 'Your next contact will become the primary one.'
              : 'They will no longer be listed for emergencies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(safetyRepositoryProvider).deleteContact(contact.id);
      ref.invalidate(emergencyContactsProvider);
    } catch (error) {
      if (context.mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _makePrimary(
    BuildContext context,
    WidgetRef ref,
    EmergencyContact contact,
  ) async {
    try {
      await ref
          .read(safetyRepositoryProvider)
          .updateContact(contact.id, makePrimary: true);
      ref.invalidate(emergencyContactsProvider);
    } catch (error) {
      if (context.mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(emergencyContactsProvider);
    final contacts = contactsAsync.value;

    final Widget body;
    if (contacts == null) {
      body = contactsAsync.hasError
          ? LoadErrorView(
              error: contactsAsync.error!,
              onRetry: () => ref.invalidate(emergencyContactsProvider),
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(
        onRefresh: () => ref.refresh(emergencyContactsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            const Card(
              color: AppColors.bhagwaLight,
              child: ListTile(
                leading: Icon(Icons.shield_outlined, color: AppColors.bhagwa),
                title: Text('Who should we reach in an emergency?'),
                subtitle: Text(
                  'If you press SOS during a ride, the Tirvona safety team '
                  'sees these contacts and can call them.',
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (contacts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Icon(
                      Icons.contact_phone_outlined,
                      size: 48,
                      color: AppColors.outlineVariant,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No emergency contacts yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('Add a family member or friend.'),
                  ],
                ),
              ),
            for (final contact in contacts)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: contact.isPrimary
                        ? AppColors.bhagwa
                        : AppColors.surfaceSand,
                    child: Text(
                      contact.name[0].toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: contact.isPrimary
                            ? Colors.white
                            : AppColors.midnightBlue,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          contact.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (contact.isPrimary) ...[
                        const SizedBox(width: 8),
                        const _PrimaryChip(),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    [
                      contact.relationship,
                      contact.phone,
                    ].whereType<String>().join(' · '),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (action) => switch (action) {
                      'call' => unawaited(callNumber(context, contact.phone)),
                      'edit' => unawaited(_edit(context, ref, contact)),
                      'primary' => unawaited(
                        _makePrimary(context, ref, contact),
                      ),
                      'delete' => unawaited(_delete(context, ref, contact)),
                      _ => null,
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'call', child: Text('Call')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (!contact.isPrimary)
                        const PopupMenuItem(
                          value: 'primary',
                          child: Text('Make primary'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Remove',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _edit(context, ref, contact),
                ),
              ),
          ],
        ),
      );
    }

    final canAdd = (contacts?.length ?? maxContacts) < maxContacts;
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contacts')),
      body: body,
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add contact'),
            )
          : null,
    );
  }
}

class _PrimaryChip extends StatelessWidget {
  const _PrimaryChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.bhagwaLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Primary',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.bhagwaDark,
        ),
      ),
    );
  }
}

class _ContactForm extends ConsumerStatefulWidget {
  const _ContactForm({this.contact});

  final EmergencyContact? contact;

  @override
  ConsumerState<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<_ContactForm> {
  static const _relationships = [
    'Father',
    'Mother',
    'Spouse',
    'Brother',
    'Sister',
    'Friend',
  ];

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.contact?.name);
  late final _phone = TextEditingController(
    text: widget.contact?.phone.replaceFirst(RegExp(r'^\+91'), ''),
  );
  late final _relationship = TextEditingController(
    text: widget.contact?.relationship,
  );
  late bool _primary = widget.contact?.isPrimary ?? false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relationship.dispose();
    super.dispose();
  }

  /// A bare 10-digit number is Indian; the server normalises and validates.
  String get _phoneValue {
    final digits = _phone.text.replaceAll(RegExp(r'[\s\-()]'), '');
    return RegExp(r'^[6-9]\d{9}$').hasMatch(digits) ? '+91$digits' : digits;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = ref.read(safetyRepositoryProvider);
    try {
      final existing = widget.contact;
      if (existing == null) {
        await repository.addContact(
          name: _name.text.trim(),
          phone: _phoneValue,
          relationship: _relationship.text.trim(),
          isPrimary: _primary,
        );
      } else {
        await repository.updateContact(
          existing.id,
          name: _name.text.trim(),
          phone: _phoneValue,
          relationship: _relationship.text.trim(),
          makePrimary: _primary && !existing.isPrimary,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.contact != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                editing ? 'Edit contact' : 'Add emergency contact',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  prefixText: '+91 ',
                  helperText:
                      'Other countries: start with + and the country code',
                  border: OutlineInputBorder(),
                ),
                validator: (_) {
                  final value = _phoneValue;
                  if (value.isEmpty) return 'Enter a mobile number';
                  if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value)) {
                    return 'Enter a valid 10-digit mobile number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _relationship,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Relationship (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final relation in _relationships)
                    ActionChip(
                      label: Text(relation),
                      onPressed: () =>
                          setState(() => _relationship.text = relation),
                    ),
                ],
              ),
              if (!(widget.contact?.isPrimary ?? false))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Primary contact'),
                  subtitle: const Text('The first person to call'),
                  value: _primary,
                  onChanged: (value) => setState(() => _primary = value),
                ),
              const SizedBox(height: 8),
              ErrorBanner(message: _error),
              LoadingFilledButton(
                label: editing ? 'Save changes' : 'Add contact',
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
