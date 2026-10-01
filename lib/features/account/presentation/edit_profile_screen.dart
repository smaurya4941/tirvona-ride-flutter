import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/loading_filled_button.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_error_messages.dart';
import '../../auth/presentation/phone_utils.dart';
import '../../auth/presentation/session_controller.dart';
import '../application/account_controller.dart';
import '../data/account_repository.dart';
import 'widgets/profile_avatar.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Name, email, gender, date of birth and photo. The mobile number is the
/// sign-in identity and is shown read-only.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final AppUser _initial = ref.read(sessionControllerProvider).user!;
  late final _firstName = TextEditingController(text: _initial.firstName);
  late final _lastName = TextEditingController(text: _initial.lastName ?? '');
  late final _email = TextEditingController(text: _initial.email ?? '');
  late Gender? _gender = _initial.gender;
  late DateTime? _dateOfBirth = _initial.dateOfBirth;
  bool _saving = false;
  bool _photoBusy = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Only what the user changed.
  ProfileUpdate _changes() {
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final email = _email.text.trim().toLowerCase();
    return ProfileUpdate(
      firstName: firstName != _initial.firstName ? firstName : null,
      lastName: lastName != (_initial.lastName ?? '') ? lastName : null,
      email: email.isNotEmpty && email != _initial.email ? email : null,
      removeEmail: email.isEmpty && _initial.email != null,
      gender: _gender != _initial.gender ? _gender : null,
      dateOfBirth: _dateOfBirth != _initial.dateOfBirth ? _dateOfBirth : null,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final changes = _changes();
    if (changes.isEmpty) {
      context.pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(accountControllerProvider).updateProfile(changes);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated')));
      context.pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.authMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePhoto(bool hasPhoto) async {
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.gallery),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text(
                  'Remove photo',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final account = ref.read(accountControllerProvider);
    if (action == _PhotoAction.remove) {
      await _photoTask(account.removeProfileImage, 'Photo removed');
      return;
    }
    final XFile? picked;
    try {
      // Downscaled on the device: a profile photo never needs more.
      picked = await _picker.pickImage(
        source: action == _PhotoAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Could not open the ${action == _PhotoAction.camera ? 'camera' : 'gallery'}. '
              'Check the app\'s permissions in Settings.',
        );
      }
      return;
    }
    if (picked == null || !mounted) return;
    final path = picked.path;
    await _photoTask(
      () => account.uploadProfileImage(path),
      'Profile photo updated',
    );
  }

  Future<void> _photoTask(Future<void> Function() task, String done) async {
    setState(() {
      _photoBusy = true;
      _error = null;
    });
    try {
      await task();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).user;
    if (user == null) return const Scaffold();
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: _PhotoEditor(
                  user: user,
                  busy: _photoBusy,
                  onTap: _saving || _photoBusy
                      ? null
                      : () => _changePhoto(user.profileImage != null),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstName,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.givenName],
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'First name',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Enter your first name'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastName,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.familyName],
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'Last name',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Email (optional)',
                  prefixIcon: const Icon(Icons.mail_outline),
                  border: const OutlineInputBorder(),
                  helperText: user.email != null && !user.isEmailVerified
                      ? 'Not verified yet'
                      : 'Receipts and account updates',
                ),
                validator: (value) {
                  final email = (value ?? '').trim();
                  if (email.isEmpty) return null;
                  if (email.length > 254 || !_emailPattern.hasMatch(email)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Gender>(
                initialValue: _gender,
                decoration: const InputDecoration(
                  labelText: 'Gender (optional)',
                  prefixIcon: Icon(Icons.wc_outlined),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final gender in Gender.values)
                    DropdownMenuItem(value: gender, child: Text(gender.label)),
                ],
                onChanged: (value) => setState(() => _gender = value),
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Date of birth (optional)',
                icon: Icons.cake_outlined,
                initialValue: _dateOfBirth,
                firstDate: DateTime(1900),
                lastDate: DateTime(now.year - 13, now.month, now.day),
                onChanged: (value) => setState(() => _dateOfBirth = value),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_outlined),
                title: Text(formatPhoneForDisplay(user.phone)),
                subtitle: const Text(
                  'Your mobile number is how you sign in. Contact support to '
                  'change it.',
                ),
                trailing: user.isPhoneVerified
                    ? const Icon(Icons.verified, color: AppColors.success)
                    : null,
              ),
              const SizedBox(height: 16),
              ErrorBanner(message: _error),
              LoadingFilledButton(
                label: 'Save changes',
                isLoading: _saving,
                onPressed: _photoBusy ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PhotoAction { camera, gallery, remove }

class _PhotoEditor extends StatelessWidget {
  const _PhotoEditor({required this.user, required this.busy, this.onTap});

  final AppUser user;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: user.profileImage == null ? 'Add profile photo' : 'Change profile photo',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ProfileAvatar(user: user, radius: 52),
            if (busy)
              const SizedBox.square(
                dimension: 104,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bhagwa,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.photo_camera_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
