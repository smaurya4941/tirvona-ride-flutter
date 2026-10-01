import 'package:flutter/foundation.dart';

enum DependencyStatus {
  up,
  down,
  disabled,
  unknown;

  static DependencyStatus parse(Object? value) =>
      DependencyStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => DependencyStatus.unknown,
      );
}

@immutable
class BackendHealth {
  const BackendHealth({
    required this.service,
    required this.isReady,
    required this.environment,
    required this.database,
    required this.redis,
    required this.checkedAt,
  });

  factory BackendHealth.fromJson(Map<String, dynamic> json) {
    final checks = json['checks'] as Map<String, dynamic>? ?? const {};
    return BackendHealth(
      service: json['service'] as String? ?? 'unknown',
      isReady: json['status'] == 'ready',
      environment: json['environment'] as String? ?? 'unknown',
      database: DependencyStatus.parse(checks['database']),
      redis: DependencyStatus.parse(checks['redis']),
      checkedAt:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String service;
  final bool isReady;
  final String environment;
  final DependencyStatus database;
  final DependencyStatus redis;
  final DateTime checkedAt;
}
