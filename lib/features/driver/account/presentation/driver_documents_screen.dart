import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/date_field.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../rides/presentation/widgets/ride_widgets.dart';
import '../../data/driver_repository.dart';
import '../../data/vehicle_repository.dart';
import '../../domain/driver_models.dart';
import '../data/driver_account_repository.dart';
import '../domain/driver_change.dart';
import 'widgets/change_request_widgets.dart';

/// Documents that carry an expiry date worth tracking.
const _expiringDriverTypes = {KycDocumentType.drivingLicense};

/// One row: a document type, what is on file, and any update in flight.
class _DocumentRowData {
  const _DocumentRowData({
    required this.label,
    required this.onFile,
    required this.status,
    required this.asksForNumber,
    required this.asksForExpiry,
    this.documentNumber,
    this.expiryDate,
    this.pending,
    this.rejected,
    this.required = false,
  });

  final String label;
  final bool onFile;
  final DocumentStatus? status;
  final bool asksForNumber;
  final bool asksForExpiry;
  final String? documentNumber;
  final DateTime? expiryDate;
  final DriverChangeRequest? pending;
  final DriverChangeRequest? rejected;
  final bool required;
}

/// An approved driver's KYC and vehicle documents. Renewals and additions go
/// to Tirvona for review; the document on file stays valid meanwhile.
class DriverDocumentsScreen extends ConsumerStatefulWidget {
  const DriverDocumentsScreen({super.key});

  @override
  ConsumerState<DriverDocumentsScreen> createState() =>
      _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends ConsumerState<DriverDocumentsScreen> {
  final _picker = ImagePicker();

  /// The document being uploaded (its label), to show progress on its row.
  String? _uploading;

  Future<void> _upload({
    required String label,
    required bool asksForNumber,
    required bool asksForExpiry,
    String? currentNumber,
    KycDocumentType? driverDocument,
    VehicleDocumentType? vehicleDocument,
    String? vehicleId,
  }) async {
    final choice = await showModalBottomSheet<DocumentUploadChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DocumentUploadSheet(
        title: label,
        asksForNumber: asksForNumber,
        asksForExpiry: asksForExpiry,
        initialNumber: currentNumber,
      ),
    );
    if (choice == null || !mounted) return;

    final XFile? picked;
    try {
      // Downscaled on the device: well under the 5 MB limit, still legible.
      picked = await _picker.pickImage(
        source: choice.source,
        imageQuality: 80,
        maxWidth: 2000,
        maxHeight: 2000,
      );
    } on Exception {
      if (mounted) {
        showErrorSnack(
          context,
          const UserFacingError(
            'Could not open the camera or gallery. Check the app\'s '
            'permissions in Settings.',
          ),
        );
      }
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _uploading = label);
    try {
      await ref
          .read(driverAccountRepositoryProvider)
          .requestDocumentChange(
            driverDocument: driverDocument,
            vehicleDocument: vehicleDocument,
            vehicleId: vehicleId,
            filePath: picked.path,
            documentNumber: choice.documentNumber,
            expiryDate: choice.expiryDate,
          );
      refreshDriverAccount(ref);
      if (vehicleId != null) {
        ref.invalidate(vehicleDocumentsProvider(vehicleId));
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label sent for review')));
      }
    } on ApiException catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _withdraw(DriverChangeRequest request) async {
    try {
      await ref.read(driverAccountRepositoryProvider).withdraw(request.id);
      refreshDriverAccount(ref);
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(driverDocumentsProvider);
    final vehicles = ref.watch(myVehiclesProvider).value ?? const <Vehicle>[];
    final vehicle = vehicles.where((item) => item.isActive).firstOrNull;
    final vehicleDocuments = vehicle == null
        ? null
        : ref.watch(vehicleDocumentsProvider(vehicle.id));
    final changes = ref.watch(driverChangesProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: documents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LoadErrorView(
          error: error,
          onRetry: () => refreshDriverAccount(ref),
        ),
        data: (documents) {
          final byType = {for (final doc in documents) doc.documentType: doc};
          final vehicleByType = {
            for (final doc
                in vehicleDocuments?.value ?? const <VehicleDocumentRecord>[])
              doc.documentType: doc,
          };
          return RefreshIndicator(
            onRefresh: () async {
              refreshDriverAccount(ref);
              if (vehicle != null) {
                ref.invalidate(vehicleDocumentsProvider(vehicle.id));
              }
              await ref.read(driverDocumentsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const Text(
                  'Keep your documents current. Updates are checked by '
                  'Tirvona; the document on file stays valid until then.',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                const _SectionTitle('Your documents'),
                for (final type in KycDocumentType.values)
                  _DocumentRow(
                    data: _DocumentRowData(
                      label: type.label,
                      required: type.required,
                      onFile: byType[type] != null,
                      status: byType[type]?.status,
                      documentNumber: byType[type]?.documentNumber,
                      expiryDate: byType[type]?.expiryDate,
                      asksForNumber: type != KycDocumentType.profilePhoto,
                      asksForExpiry: _expiringDriverTypes.contains(type),
                      pending: changes?.pendingFor(
                        DriverChangeKind.driverDocument,
                        documentType: type.wireName,
                      ),
                      rejected: changes?.lastRejectedFor(
                        DriverChangeKind.driverDocument,
                        documentType: type.wireName,
                      ),
                    ),
                    uploading: _uploading == type.label,
                    enabled: _uploading == null,
                    onUpload: () => _upload(
                      label: type.label,
                      asksForNumber: type != KycDocumentType.profilePhoto,
                      asksForExpiry: _expiringDriverTypes.contains(type),
                      currentNumber: byType[type]?.documentNumber,
                      driverDocument: type,
                    ),
                    onWithdraw: _withdraw,
                  ),
                const SizedBox(height: 16),
                const _SectionTitle('Vehicle documents'),
                if (vehicle == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No active vehicle on your account.'),
                  )
                else if (vehicleDocuments!.hasError &&
                    !vehicleDocuments.hasValue)
                  LoadErrorView(
                    error: vehicleDocuments.error!,
                    onRetry: () =>
                        ref.invalidate(vehicleDocumentsProvider(vehicle.id)),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${vehicle.vehicleType.label} · ${vehicle.registrationNumber}',
                      style: const TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                  ),
                  for (final type in VehicleDocumentType.values)
                    _DocumentRow(
                      data: _DocumentRowData(
                        label: type.label,
                        onFile: vehicleByType[type] != null,
                        status: vehicleByType[type]?.status,
                        documentNumber: vehicleByType[type]?.documentNumber,
                        expiryDate: vehicleByType[type]?.expiryDate,
                        asksForNumber: true,
                        asksForExpiry: true,
                        pending: changes?.pendingFor(
                          DriverChangeKind.vehicleDocument,
                          documentType: type.wireName,
                          vehicleId: vehicle.id,
                        ),
                        rejected: changes?.lastRejectedFor(
                          DriverChangeKind.vehicleDocument,
                          documentType: type.wireName,
                          vehicleId: vehicle.id,
                        ),
                      ),
                      uploading: _uploading == type.label,
                      enabled: _uploading == null,
                      onUpload: () => _upload(
                        label: type.label,
                        asksForNumber: true,
                        asksForExpiry: true,
                        currentNumber: vehicleByType[type]?.documentNumber,
                        vehicleDocument: type,
                        vehicleId: vehicle.id,
                      ),
                      onWithdraw: _withdraw,
                    ),
                ],
                if (changes != null && changes.history.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const _SectionTitle('Recent updates'),
                  Card(
                    child: Column(
                      children: [
                        for (final request in changes.history.take(10))
                          ListTile(
                            dense: true,
                            title: Text(request.label),
                            subtitle: Text(
                              [
                                formatDate(
                                  request.reviewedAt ?? request.submittedAt,
                                ),
                                if (request.reviewNote != null)
                                  request.reviewNote!,
                              ].join(' · '),
                            ),
                            trailing: ChangeStatusChip(status: request.status),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.data,
    required this.uploading,
    required this.enabled,
    required this.onUpload,
    required this.onWithdraw,
  });

  final _DocumentRowData data;
  final bool uploading;
  final bool enabled;
  final VoidCallback onUpload;
  final ValueChanged<DriverChangeRequest> onWithdraw;

  @override
  Widget build(BuildContext context) {
    final (statusText, statusColor) = !data.onFile
        ? (
            data.required ? 'Missing' : 'Not on file',
            AppColors.onSurfaceVariant,
          )
        : switch (data.status) {
            DocumentStatus.verified => ('Verified', AppColors.success),
            DocumentStatus.rejected => ('Rejected', AppColors.error),
            _ => ('On file', AppColors.onSurfaceVariant),
          };
    final expiry = data.expiryDate == null
        ? null
        : expiryStatus(data.expiryDate!);
    final pending = data.pending;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  data.onFile ? Icons.description_outlined : Icons.upload_file,
                  color: statusColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          statusText,
                          if (data.documentNumber != null) data.documentNumber!,
                        ].join(' · '),
                        style: TextStyle(color: statusColor, fontSize: 13),
                      ),
                      if (expiry != null)
                        Text(
                          expiry.text,
                          style: TextStyle(color: expiry.color, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (uploading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  TextButton(
                    onPressed: enabled ? onUpload : null,
                    child: Text(
                      pending != null
                          ? 'Replace'
                          : data.onFile
                          ? 'Update'
                          : 'Add',
                    ),
                  ),
              ],
            ),
            if (pending != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Row(
                  children: [
                    const ChangeStatusChip(status: DriverChangeStatus.pending),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'New copy sent ${formatDate(pending.submittedAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: enabled ? () => onWithdraw(pending) : null,
                      child: const Text('Withdraw'),
                    ),
                  ],
                ),
              )
            else if (data.rejected case final rejected?)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text(
                  'Last update not approved'
                  '${rejected.reviewNote == null ? '' : ': ${rejected.reviewNote}'}',
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
