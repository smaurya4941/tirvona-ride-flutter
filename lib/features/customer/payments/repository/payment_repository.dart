import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../models/payment_models.dart';

/// Customer payment calls. Nothing here sends an amount: the server prices
/// the ride, and learns an online method from Razorpay.
class PaymentRepository {
  const PaymentRepository(this._dio);

  final Dio _dio;

  /// Opens (or re-opens) payment for a completed ride.
  Future<PaymentCheckout> create(String rideId) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.paymentsCreate,
      data: {'rideId': rideId},
    );
    return PaymentCheckout.fromJson(_data(response));
  });

  /// "I'll pay the driver in cash": the server marks the ride paid (method
  /// cash) for its final fare.
  Future<PaymentRecord> payCash(String rideId) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.paymentsCash,
      data: {'rideId': rideId},
    );
    return PaymentRecord.fromJson(_data(response));
  });

  /// Forwards Razorpay's success callback for server-side verification.
  Future<PaymentRecord> verify({
    required String paymentId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.paymentsVerify,
      data: {
        'paymentId': paymentId,
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
      },
    );
    return PaymentRecord.fromJson(_data(response));
  });

  /// Tells the server the checkout failed or was closed (advisory).
  Future<PaymentRecord> reportFailure(
    String paymentId, {
    String? razorpayOrderId,
    String? razorpayPaymentId,
    String? code,
    String? description,
    bool cancelled = false,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.paymentFailure(paymentId),
      data: {
        'razorpayOrderId': ?razorpayOrderId,
        'razorpayPaymentId': ?razorpayPaymentId,
        'code': ?code,
        if (description != null && description.isNotEmpty)
          'description': description.length > 500
              ? description.substring(0, 500)
              : description,
        'cancelled': cancelled,
      },
    );
    return PaymentRecord.fromJson(_data(response));
  });

  Future<PaymentReceipt> receipt(String paymentId) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.payment(paymentId),
    );
    return PaymentReceipt.fromJson(_data(response));
  });

  Future<PaymentHistoryPage> history({int page = 1, int limit = 20}) =>
      _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.paymentsHistory,
          queryParameters: {'page': page, 'limit': limit},
        );
        return PaymentHistoryPage.fromJson(_data(response));
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

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => PaymentRepository(ref.watch(dioProvider)),
);
