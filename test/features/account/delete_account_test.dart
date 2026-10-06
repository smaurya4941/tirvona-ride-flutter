import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/app/router/app_router.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/core/config/app_config.dart';
import 'package:tirvona_ride/core/config/app_config_provider.dart';
import 'package:tirvona_ride/core/network/api_exception.dart';
import 'package:tirvona_ride/features/account/data/account_repository.dart';
import 'package:tirvona_ride/features/account/presentation/delete_account_screen.dart';
import 'package:tirvona_ride/features/account/presentation/settings_screen.dart';
import 'package:tirvona_ride/features/auth/domain/app_user.dart';
import 'package:tirvona_ride/features/auth/domain/auth_session.dart';
import 'package:tirvona_ride/features/auth/presentation/auth_error_messages.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';

const _customer = AppUser(
  id: 'u1',
  phone: '+919876543210',
  role: UserRole.customer,
  status: UserStatus.active,
  firstName: 'Asha',
  isPhoneVerified: true,
);

AppUser _driver(DriverStatus status) => AppUser(
  id: 'd1',
  phone: '+919876543211',
  role: UserRole.driver,
  status: UserStatus.active,
  firstName: 'Ravi',
  isPhoneVerified: true,
  driver: DriverStatusInfo(driverStatus: status),
);

class _FakeAccount extends AccountRepository {
  _FakeAccount() : super(Dio());

  final deleted = <String>[];
  ApiException? error;

  @override
  Future<void> deleteAccount({required String password}) async {
    final failure = error;
    if (failure != null) throw failure;
    deleted.add(password);
  }
}

void main() {
  late _FakeAccount account;
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    account = _FakeAccount();
    container = ProviderContainer(
      overrides: [accountRepositoryProvider.overrideWithValue(account)],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpScreen(WidgetTester tester, {bool isDriver = false}) async {
    await container
        .read(sessionControllerProvider.notifier)
        .activate(
          AuthSession(
            user: isDriver ? _driver(DriverStatus.approved) : _customer,
            accessToken: 'a',
            refreshToken: 'r',
          ),
        );
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: DeleteAccountScreen(isDriver: isDriver)),
      ),
    );
  }

  Future<void> submit(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(TextFormField), password);
    final button = find.text('Delete my account');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    // The button's spinner never settles while the request is "running"
    // (the real app swaps screens on sign-out), so pump a few frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('needs the password before anything is sent', (tester) async {
    await pumpScreen(tester);
    final button = find.text('Delete my account');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Enter your password'), findsOneWidget);
    expect(find.text('Delete your account?'), findsNothing);
    expect(account.deleted, isEmpty);
  });

  testWidgets('"Keep my account" sends nothing', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextFormField), 'Password@123');
    final button = find.text('Delete my account');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep my account'));
    await tester.pumpAndSettle();
    expect(account.deleted, isEmpty);
    expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);
  });

  testWidgets('deleting signs this device out', (tester) async {
    await pumpScreen(tester);
    await submit(tester, 'Password@123');
    expect(account.deleted, ['Password@123']);
    expect(container.read(sessionControllerProvider).isAuthenticated, isFalse);
  });

  testWidgets('a wrong password stays on the screen with a clear message', (
    tester,
  ) async {
    account.error = const ApiException(
      kind: ApiErrorKind.client,
      statusCode: 400,
      code: AuthErrorCodes.accountDeletionPasswordInvalid,
      message: 'Password is incorrect',
    );
    await pumpScreen(tester);
    await submit(tester, 'nope-nope');
    expect(find.text('That password is not correct.'), findsOneWidget);
    expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);
  });

  testWidgets('an unsettled ride or earning shows the server reason', (
    tester,
  ) async {
    account.error = const ApiException(
      kind: ApiErrorKind.client,
      statusCode: 409,
      code: AuthErrorCodes.accountDeletionBlocked,
      message: 'You have a ride in progress.',
    );
    await pumpScreen(tester, isDriver: true);
    await submit(tester, 'Password@123');
    expect(find.text('You have a ride in progress.'), findsOneWidget);
    expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);
  });

  testWidgets('drivers are told their documents and vehicle are erased', (
    tester,
  ) async {
    await pumpScreen(tester, isDriver: true);
    expect(find.textContaining('licence details'), findsOneWidget);
    expect(find.textContaining('earnings that are not yet paid'), findsOneWidget);
  });

  group('settings', () {
    late ProviderContainer scoped;

    Future<void> pumpSettings(
      WidgetTester tester,
      AppEnvironment environment,
    ) async {
      await container
          .read(sessionControllerProvider.notifier)
          .activate(
            const AuthSession(
              user: _customer,
              accessToken: 'a',
              refreshToken: 'r',
            ),
          );
      tester.view
        ..physicalSize = const Size(412, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      scoped = ProviderContainer(
        parent: container,
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(environment: environment, apiOrigin: 'https://x.test'),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scoped,
          child: const MaterialApp(home: SettingsScreen(isDriver: false)),
        ),
      );
      await tester.pump();
    }

    // Unmount inside the test so provider disposal timers run before it ends.
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      scoped.dispose();
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('offers the legal pages and account deletion', (tester) async {
      await pumpSettings(tester, AppEnvironment.production);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Terms of use'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Delete account'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Delete account'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the developer status page is hidden in production only', (
      tester,
    ) async {
      await pumpSettings(tester, AppEnvironment.production);
      expect(find.text('System status'), findsNothing);
      await pumpSettings(tester, AppEnvironment.development);
      expect(find.text('System status'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('routing', () {
    test('every driver state can reach the delete screen', () {
      for (final status in DriverStatus.values) {
        expect(
          resolveRedirect(
            SessionState.authenticated(_driver(status)),
            AppRoutes.driverDeleteAccount,
          ),
          isNull,
          reason: status.name,
        );
      }
      expect(
        resolveRedirect(
          const SessionState.authenticated(_customer),
          AppRoutes.customerDeleteAccount,
        ),
        isNull,
      );
      // But a customer cannot reach the driver's copy.
      expect(
        resolveRedirect(
          const SessionState.authenticated(_customer),
          AppRoutes.driverDeleteAccount,
        ),
        AppRoutes.customerHome,
      );
    });
  });

  test('legal page URLs live under the API version path', () {
    const config = AppConfig(
      environment: AppEnvironment.production,
      apiOrigin: 'https://ride.example.com',
    );
    expect(config.privacyPolicyUrl, 'https://ride.example.com/api/v1/legal/privacy');
    expect(config.termsUrl, 'https://ride.example.com/api/v1/legal/terms');
    expect(
      config.deleteAccountUrl,
      'https://ride.example.com/api/v1/legal/delete-account',
    );
  });
}
