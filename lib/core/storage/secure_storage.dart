import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper around [FlutterSecureStorage] for the auth token pair and
/// small per-user app data (e.g. recent places, which are location history).
/// Keychain (iOS) / EncryptedSharedPreferences (Android) back the platform
/// implementations, so tokens never sit in plaintext on device.
class SecureStorage {
  SecureStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _accessTokenKey = 'auth.accessToken';
  static const _refreshTokenKey = 'auth.refreshToken';
  static const _deviceIdKey = 'auth.deviceId';

  final FlutterSecureStorage _storage;

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) => Future.wait([
    _storage.write(key: _accessTokenKey, value: accessToken),
    _storage.write(key: _refreshTokenKey, value: refreshToken),
  ]).then((_) {});

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> clearTokens() => Future.wait([
    _storage.delete(key: _accessTokenKey),
    _storage.delete(key: _refreshTokenKey),
  ]).then((_) {});

  /// A stable per-install id sent as `deviceId` on login/register so the
  /// backend's `user_sessions` entries are identifiable across refreshes.
  Future<String> readOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null) return existing;
    final generated = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await _storage.write(key: _deviceIdKey, value: generated);
    return generated;
  }

  /// Small feature-owned values; callers namespace their [key].
  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);
}

final secureStorageProvider = Provider<SecureStorage>((ref) => SecureStorage());
