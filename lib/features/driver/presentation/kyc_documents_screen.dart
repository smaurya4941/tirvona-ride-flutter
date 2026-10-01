import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../shared/widgets/loading_filled_button.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/driver_repository.dart';
import '../domain/driver_models.dart';
import 'widgets/onboarding_steps.dart';

/// Onboarding step 3: upload KYC documents, then submit for admin review.
/// Submitting moves the driver to UNDER_REVIEW; refreshing the session makes
/// the router switch to the pending-approval screen.
class KycDocumentsScreen extends ConsumerStatefulWidget {
  const KycDocumentsScreen({super.key});

  @override
  ConsumerState<KycDocumentsScreen> createState() => _KycDocumentsScreenState();
}

class _KycDocumentsScreenState extends ConsumerState<KycDocumentsScreen> {
  final _picker = ImagePicker();
  KycDocumentType? _uploading;
  bool _submitting = false;
  String? _error;

  Future<void> _upload(KycDocumentType type) async {
    final choice = await showModalBottomSheet<_UploadChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _UploadSheet(type: type),
    );
    if (choice == null) return;

    // Downscaled on-device so a modern phone photo stays well under the
    // backend's 5 MB limit.
    final picked = await _picker.pickImage(
      source: choice.source,
      imageQuality: 80,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (picked == null) return;

    setState(() {
      _uploading = type;
      _error = null;
    });
    try {
      await ref
          .read(driverRepositoryProvider)
          .uploadDocument(
            type: type,
            filePath: picked.path,
            documentNumber: choice.documentNumber,
          );
      ref.invalidate(driverDocumentsProvider);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _remove(KycDocument document) async {
    setState(() => _error = null);
    try {
      await ref.read(driverRepositoryProvider).deleteDocument(document.id);
      ref.invalidate(driverDocumentsProvider);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(driverRepositoryProvider).submitKyc();
      await ref.read(sessionControllerProvider.notifier).refreshUser();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = _describeSubmitError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _describeSubmitError(ApiException error) {
    final data = error.data;
    if (error.code != 'DRIVER_KYC_INCOMPLETE' ||
        data is! Map<String, dynamic>) {
      return error.message;
    }
    final missing = <String>[
      if (data['missingLicense'] == true) 'licence details',
      if (data['missingVehicle'] == true) 'vehicle details',
      ...((data['missingDocuments'] as List<dynamic>?) ?? const []).map(
        (type) => KycDocumentType.fromWire(type as String).label,
      ),
    ];
    return missing.isEmpty
        ? error.message
        : 'Still needed: ${missing.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(driverDocumentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('KYC documents')),
      body: SafeArea(
        child: documents.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => LoadErrorView(
            error: error,
            onRetry: () => ref.invalidate(driverDocumentsProvider),
          ),
          data: (documents) {
            final byType = {for (final doc in documents) doc.documentType: doc};
            final requiredComplete = KycDocumentType.values
                .where((type) => type.required)
                .every(byType.containsKey);
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const OnboardingSteps(current: 2),
                const SizedBox(height: 24),
                Text(
                  'Upload clear photos. Documents marked * are required.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                for (final type in KycDocumentType.values)
                  _DocumentTile(
                    type: type,
                    document: byType[type],
                    isUploading: _uploading == type,
                    enabled: _uploading == null && !_submitting,
                    onUpload: () => _upload(type),
                    onRemove: byType[type] == null
                        ? null
                        : () => _remove(byType[type]!),
                  ),
                const SizedBox(height: 16),
                ErrorBanner(message: _error),
                LoadingFilledButton(
                  label: 'Submit for review',
                  icon: Icons.send_outlined,
                  isLoading: _submitting,
                  onPressed: (requiredComplete && _uploading == null)
                      ? _submit
                      : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.type,
    required this.document,
    required this.isUploading,
    required this.enabled,
    required this.onUpload,
    required this.onRemove,
  });

  final KycDocumentType type;
  final KycDocument? document;
  final bool isUploading;
  final bool enabled;
  final VoidCallback onUpload;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final document = this.document;
    final (statusLabel, statusColor) = switch (document?.status) {
      null => ('Not uploaded', AppColors.onSurfaceVariant),
      DocumentStatus.pending => ('Uploaded', AppColors.warning),
      DocumentStatus.verified => ('Verified', AppColors.success),
      DocumentStatus.rejected => ('Rejected', AppColors.error),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              document == null ? Icons.upload_file : Icons.description_outlined,
              color: statusColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.required ? '${type.label} *' : type.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusLabel,
                    style: TextStyle(color: statusColor, fontSize: 13),
                  ),
                  if (document?.rejectionReason != null)
                    Text(
                      document!.rejectionReason!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (isUploading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              if (document?.status == DocumentStatus.pending)
                IconButton(
                  tooltip: 'Remove',
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              TextButton(
                onPressed: enabled ? onUpload : null,
                child: Text(document == null ? 'Upload' : 'Replace'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UploadChoice {
  const _UploadChoice(this.source, this.documentNumber);

  final ImageSource source;
  final String? documentNumber;
}

class _UploadSheet extends StatefulWidget {
  const _UploadSheet({required this.type});

  final KycDocumentType type;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  final _number = TextEditingController();

  bool get _asksForNumber => widget.type != KycDocumentType.profilePhoto;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _pick(ImageSource source) {
    final number = _number.text.trim();
    Navigator.of(context)
        .pop(_UploadChoice(source, number.isEmpty ? null : number));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.type.label,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (_asksForNumber) ...[
            TextField(
              controller: _number,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Document number (optional)',
                border: OutlineInputBorder(),
              ),
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
    );
  }
}
