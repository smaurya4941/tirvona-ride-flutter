import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/core/config/app_config.dart';
import 'package:tirvona_ride/core/config/app_config_provider.dart';
import 'package:tirvona_ride/core/network/api_exception.dart';
import 'package:tirvona_ride/features/system/data/system_repository.dart';
import 'package:tirvona_ride/features/system/domain/backend_health.dart';
import 'package:tirvona_ride/features/system/presentation/system_status_screen.dart';

class _FakeSystemRepository implements SystemRepository {
  _FakeSystemRepository(this._result);

  final Future<BackendHealth> Function() _result;

  @override
  Future<BackendHealth> checkHealth() => _result();
}

Widget _harness(SystemRepository repository) => ProviderScope(
  overrides: [
    appConfigProvider.overrideWithValue(
      const AppConfig(
        environment: AppEnvironment.development,
        apiOrigin: 'http://test:5100',
      ),
    ),
    systemRepositoryProvider.overrideWithValue(repository),
  ],
  child: const MaterialApp(home: SystemStatusScreen()),
);

void main() {
  testWidgets('shows connected dependencies when the API is ready', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _FakeSystemRepository(
          () async => BackendHealth(
            service: 'tirvona-ride-api',
            isReady: true,
            environment: 'development',
            database: DependencyStatus.up,
            redis: DependencyStatus.up,
            checkedAt: DateTime(2026),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('http://test:5100/api/v1'), findsOneWidget);
    expect(find.text('Ready (development)'), findsOneWidget);
    expect(find.text('Connected'), findsNWidgets(2));
  });

  testWidgets('shows the API error message when the backend is unreachable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _FakeSystemRepository(
          () async => throw ApiException.fromDio(
            DioException(
              requestOptions: RequestOptions(path: '/health'),
              type: DioExceptionType.connectionError,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Cannot reach Tirvona Rides. Check your connection.'),
      findsOneWidget,
    );
  });

  testWidgets('retries when "Check again" is tapped', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _harness(
        _FakeSystemRepository(() async {
          calls++;
          return BackendHealth(
            service: 'tirvona-ride-api',
            isReady: false,
            environment: 'development',
            database: DependencyStatus.up,
            redis: DependencyStatus.down,
            checkedAt: DateTime(2026),
          );
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Degraded'), findsOneWidget);
    expect(find.text('Unreachable'), findsOneWidget);

    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
