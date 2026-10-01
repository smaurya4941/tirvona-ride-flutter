import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/domain/app_user.dart';

/// What `PATCH /users/me` changes. Only non-null fields are sent, except
/// [removeEmail], which clears the address.
class ProfileUpdate {
  const ProfileUpdate({
    this.firstName,
    this.lastName,
    this.email,
    this.removeEmail = false,
    this.gender,
    this.dateOfBirth,
  });

  final String? firstName;
  final String? lastName;
  final String? email;
  final bool removeEmail;
  final Gender? gender;
  final DateTime? dateOfBirth;

  bool get isEmpty =>
      firstName == null &&
      lastName == null &&
      email == null &&
      !removeEmail &&
      gender == null &&
      dateOfBirth == null;

  Map<String, dynamic> toJson() => {
    'firstName': ?firstName,
    'lastName': ?lastName,
    if (removeEmail) 'email': null else 'email': ?email,
    'gender': ?gender?.name,
    if (dateOfBirth != null) 'dob': _isoDate(dateOfBirth!),
  };

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// The signed-in user's own account: profile fields, password and photo.
class AccountRepository {
  const AccountRepository(this._dio);

  final Dio _dio;

  Future<AppUser> updateProfile(ProfileUpdate update) => _guard(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.usersMe,
      data: update.toJson(),
    );
    return AppUser.fromJson(_data(response));
  });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _guard(() async {
    await _dio.patch<void>(
      ApiEndpoints.usersMePassword,
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  });

  /// Uploads [filePath] (already downscaled on the device) as the photo.
  Future<AppUser> uploadProfileImage(String filePath) => _guard(() async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.usersProfileImage,
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        // A phone photo on a slow mobile connection.
        sendTimeout: const Duration(minutes: 2),
      ),
    );
    return AppUser.fromJson(_data(response));
  });

  Future<AppUser> removeProfileImage() => _guard(() async {
    final response = await _dio.delete<Map<String, dynamic>>(
      ApiEndpoints.usersProfileImage,
    );
    return AppUser.fromJson(_data(response));
  });

  /// The photo at [path] (`AppUser.profileImage`). Private to the user, so
  /// it goes through the authenticated client rather than a plain image URL.
  Future<Uint8List> profileImage(String path) => _guard(() async {
    final response = await _dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Empty profile photo');
    }
    return Uint8List.fromList(bytes);
  });

  static Map<String, dynamic> _data(Response<Map<String, dynamic>> response) =>
      response.data!['data'] as Map<String, dynamic>;

  static Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(dioProvider)),
);
