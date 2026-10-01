import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../models/app_notification.dart';

/// Notification centre and device-token calls. Every route is scoped by the
/// server to the signed-in user; nothing here names a user.
class NotificationRepository {
  const NotificationRepository(this._dio);

  final Dio _dio;

  Future<NotificationPage> list({
    int page = 1,
    int limit = 20,
    bool unreadOnly = false,
  }) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.notifications,
      queryParameters: {
        'page': page,
        'limit': limit,
        if (unreadOnly) 'unreadOnly': true,
      },
    );
    return NotificationPage.fromJson(_data(response));
  });

  Future<int> unreadCount() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.notificationsUnreadCount,
    );
    return (_data(response)['unreadCount'] as num).toInt();
  });

  Future<AppNotification> markRead(String id) => _guard(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.notificationRead(id),
    );
    return AppNotification.fromJson(_data(response));
  });

  Future<void> markAllRead() => _guard(() async {
    await _dio.patch<Map<String, dynamic>>(ApiEndpoints.notificationsReadAll);
  });

  /// Registers (or refreshes) this device's FCM token for the signed-in user.
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    required String deviceId,
  }) => _guard(() async {
    await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.notificationsDeviceToken,
      data: {'token': token, 'platform': platform, 'deviceId': deviceId},
    );
  });

  /// Stops pushes to this device (sign out). Best effort.
  Future<void> deactivateDeviceToken(String token) => _guard(() async {
    await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.notificationsDeviceTokenDeactivate,
      data: {'token': token},
    );
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

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(dioProvider)),
);
