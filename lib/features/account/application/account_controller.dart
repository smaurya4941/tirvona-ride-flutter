import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/app_user.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/account_repository.dart';

/// Account changes made from Settings. Each one updates the signed-in user
/// in [SessionController], so every screen showing the name or photo
/// refreshes at once.
class AccountController {
  const AccountController(this._ref);

  final Ref _ref;

  AccountRepository get _repository => _ref.read(accountRepositoryProvider);

  Future<void> updateProfile(ProfileUpdate update) async {
    if (update.isEmpty) return;
    _publish(await _repository.updateProfile(update));
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _repository.changePassword(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  /// Deletes the account on the server, then signs this device out.
  Future<void> deleteAccount({required String password}) async {
    await _repository.deleteAccount(password: password);
    await _ref.read(sessionControllerProvider.notifier).handleAccountDeleted();
  }

  Future<void> uploadProfileImage(String filePath) async {
    _publish(await _repository.uploadProfileImage(filePath));
  }

  Future<void> removeProfileImage() async {
    _publish(await _repository.removeProfileImage());
  }

  void _publish(AppUser user) {
    final session = _ref.read(sessionControllerProvider.notifier);
    final previous = _ref.read(sessionControllerProvider).user;
    session.updateUser(user.withDriverFrom(previous));
  }
}

final accountControllerProvider = Provider<AccountController>(
  AccountController.new,
);

/// The bytes of a profile photo, by its versioned path. A new photo has a
/// new path, so a cached entry never goes stale; signing in as someone else
/// drops the cache.
final profileImageProvider = FutureProvider.family<Uint8List, String>((
  ref,
  path,
) {
  ref.watch(sessionControllerProvider.select((session) => session.user?.id));
  return ref.read(accountRepositoryProvider).profileImage(path);
});
