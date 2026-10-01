import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/features/system/domain/backend_health.dart';

void main() {
  test('parses a ready report from the API', () {
    final health = BackendHealth.fromJson({
      'service': 'tirvona-ride-api',
      'status': 'ready',
      'environment': 'development',
      'checks': {'database': 'up', 'redis': 'disabled'},
      'timestamp': '2026-09-22T10:00:00.000Z',
    });
    expect(health.isReady, isTrue);
    expect(health.database, DependencyStatus.up);
    expect(health.redis, DependencyStatus.disabled);
    expect(health.checkedAt, DateTime.utc(2026, 9, 22, 10));
  });

  test('tolerates missing and unrecognised fields', () {
    final health = BackendHealth.fromJson({
      'status': 'degraded',
      'checks': {'database': 'sideways'},
    });
    expect(health.isReady, isFalse);
    expect(health.database, DependencyStatus.unknown);
    expect(health.redis, DependencyStatus.unknown);
  });
}
