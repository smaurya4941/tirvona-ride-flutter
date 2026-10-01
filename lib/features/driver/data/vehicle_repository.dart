import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../domain/driver_models.dart';

class VehicleRepository {
  const VehicleRepository(this._dio);

  final Dio _dio;

  Future<List<Vehicle>> myVehicles() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiEndpoints.vehiclesMy,
      );
      return (response.data!['data'] as List<dynamic>)
          .map((item) => Vehicle.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Vehicle> create({
    required VehicleType vehicleType,
    required String registrationNumber,
    String? make,
    String? model,
    String? color,
    int? manufactureYear,
  }) => _save(
    () => _dio.post<Map<String, dynamic>>(
      ApiEndpoints.vehicles,
      data: _body(
        vehicleType,
        registrationNumber,
        make,
        model,
        color,
        manufactureYear,
      ),
    ),
  );

  Future<Vehicle> update(
    String id, {
    required VehicleType vehicleType,
    required String registrationNumber,
    String? make,
    String? model,
    String? color,
    int? manufactureYear,
  }) => _save(
    () => _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.vehicle(id),
      data: _body(
        vehicleType,
        registrationNumber,
        make,
        model,
        color,
        manufactureYear,
      ),
    ),
  );

  static Map<String, dynamic> _body(
    VehicleType vehicleType,
    String registrationNumber,
    String? make,
    String? model,
    String? color,
    int? manufactureYear,
  ) => {
    'vehicleType': vehicleType.wireName,
    'registrationNumber': registrationNumber
        .replaceAll(RegExp(r'\s'), '')
        .toUpperCase(),
    if (make != null && make.isNotEmpty) 'make': make,
    if (model != null && model.isNotEmpty) 'model': model,
    if (color != null && color.isNotEmpty) 'color': color,
    'manufactureYear': ?manufactureYear,
  };

  static Future<Vehicle> _save(
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    try {
      final response = await request();
      return Vehicle.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final vehicleRepositoryProvider = Provider<VehicleRepository>(
  (ref) => VehicleRepository(ref.watch(dioProvider)),
);

final myVehiclesProvider = FutureProvider.autoDispose<List<Vehicle>>(
  (ref) => ref.watch(vehicleRepositoryProvider).myVehicles(),
);
