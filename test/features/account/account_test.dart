import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tirvona_ride/app/router/app_router.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/core/network/api_exception.dart';
import 'package:tirvona_ride/features/account/data/account_repository.dart';
import 'package:tirvona_ride/features/account/presentation/change_password_screen.dart';
import 'package:tirvona_ride/features/account/presentation/edit_profile_screen.dart';
import 'package:tirvona_ride/features/auth/data/auth_repository.dart';
import 'package:tirvona_ride/features/auth/domain/app_user.dart';
import 'package:tirvona_ride/features/auth/domain/auth_session.dart';
import 'package:tirvona_ride/features/auth/domain/otp_challenge.dart';
import 'package:tirvona_ride/features/auth/domain/password_reset_ticket.dart';
import 'package:tirvona_ride/features/auth/presentation/auth_error_messages.dart';
import 'package:tirvona_ride/features/auth/presentation/forgot_password_screens.dart';
import 'package:tirvona_ride/features/auth/presentation/password_reset_flow.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';
import 'package:tirvona_ride/features/auth/presentation/widgets/password_field.dart';
import 'package:tirvona_ride/features/places/domain/saved_place.dart';

const _phone = '+919876543210';
const _rightCode = '123456';

ApiException _apiError(String code, String message, {int status = 400}) =>
    ApiException(
      kind: ApiErrorKind.client,
      statusCode: status,
      code: code,
      message: message,
    );

const _customer = AppUser(
  id: 'u1',
  phone: _phone,
  email: 'asha@example.com',
  role: UserRole.customer,
  status: UserStatus.active,
  firstName: 'Asha',
  lastName: 'Verma',
  isPhoneVerified: true,
);

AppUser _driver(DriverStatus status) => AppUser(
  id: 'd1',
  phone: _phone,
  role: UserRole.driver,
  status: UserStatus.active,
  firstName: 'Ravi',
  isPhoneVerified: true,
  driver: DriverStatusInfo(driverStatus: status),
);

OtpChallenge _challenge() => OtpChallenge.fromJson({
  'phone': _phone,
  'maskedPhone': '+91 ***** *3210',
  'channel': 'WHATSAPP',
  'codeLength': 6,
  'expiresInSeconds': 300,
  'resendAvailableInSeconds': 60,
  'sendsRemaining': 4,
  'codeSent': true,
});

class _FakeAuth extends AuthRepository {
  _FakeAuth() : super(Dio());

  final forgotFor = <String>[];
  final resets = <Map<String, String>>[];
  ApiException? forgotError;
  ApiException? resetError;
  int logoutEverywhereCalls = 0;

  @override
  Future<OtpChallenge> forgotPassword(String phone) async {
    forgotFor.add(phone);
    final error = forgotError;
    if (error != null) throw error;
    return _challenge();
  }

  @override
  Future<PasswordResetTicket> verifyPasswordResetOtp({
    required String phone,
    required String otp,
  }) async {
    if (otp != _rightCode) {
      throw _apiError(AuthErrorCodes.otpInvalid, 'Incorrect verification code');
    }
    return PasswordResetTicket.fromJson({
      'resetToken': 'reset-token-0123456789',
      'expiresInSeconds': 600,
    });
  }

  @override
  Future<AuthSession> resetPassword({
    required String resetToken,
    required String newPassword,
    required String deviceId,
  }) async {
    final error = resetError;
    if (error != null) throw error;
    resets.add({'token': resetToken, 'password': newPassword});
    return const AuthSession(
      user: _customer,
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }

  @override
  Future<void> logoutEverywhere() async => logoutEverywhereCalls++;

  @override
  Future<void> logout(String refreshToken) async {}
}

class _FakeAccount extends AccountRepository {
  _FakeAccount() : super(Dio());

  final updates = <Map<String, dynamic>>[];
  final passwordChanges = <Map<String, String>>[];
  ApiException? passwordError;

  @override
  Future<AppUser> updateProfile(ProfileUpdate update) async {
    updates.add(update.toJson());
    // The server answers without the driver status.
    return AppUser(
      id: _customer.id,
      phone: _customer.phone,
      role: UserRole.driver,
      status: UserStatus.active,
      firstName: update.firstName ?? 'Ravi',
      isPhoneVerified: true,
    );
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final error = passwordError;
    if (error != null) throw error;
    passwordChanges.add({'current': currentPassword, 'new': newPassword});
  }
}

void main() {
  late _FakeAuth auth;
  late _FakeAccount account;
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    auth = _FakeAuth();
    account = _FakeAccount();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        accountRepositoryProvider.overrideWithValue(account),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> signIn(AppUser user) => container
      .read(sessionControllerProvider.notifier)
      .activate(
        AuthSession(user: user, accessToken: 'a', refreshToken: 'r'),
      );

  Future<GoRouter> pump(
    WidgetTester tester,
    String initialLocation,
    Map<String, Widget Function(GoRouterState state)> screens,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        for (final entry in screens.entries)
          GoRoute(
            path: entry.key,
            builder: (context, state) => entry.value(state),
          ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    return router;
  }

  /// Opens [location] on top of a home route, the way the app pushes it.
  Future<void> pushOver(
    WidgetTester tester,
    String location,
    Widget screen,
  ) async {
    final router = await pump(tester, '/', {
      '/': (_) => const Scaffold(body: Text('home')),
      location: (_) => screen,
    });
    unawaited(router.push(location));
    await tester.pumpAndSettle();
  }

  group('routing', () {
    test('guests can reach every forgot-password step', () {
      const guest = SessionState.unauthenticated();
      for (final route in [
        AppRoutes.forgotPassword,
        AppRoutes.forgotPasswordVerify,
        AppRoutes.forgotPasswordNew,
      ]) {
        expect(resolveRedirect(guest, route), isNull, reason: route);
      }
      // A signed-in user never lands on them.
      expect(
        resolveRedirect(
          const SessionState.authenticated(_customer),
          AppRoutes.forgotPassword,
        ),
        AppRoutes.customerHome,
      );
    });

    test('settings are open to customers and approved drivers only', () {
      const customer = SessionState.authenticated(_customer);
      for (final route in [
        AppRoutes.customerSettings,
        AppRoutes.customerEditProfile,
        AppRoutes.customerChangePassword,
        AppRoutes.customerSavedPlaces,
      ]) {
        expect(resolveRedirect(customer, route), isNull, reason: route);
      }
      expect(
        resolveRedirect(customer, AppRoutes.driverSettings),
        AppRoutes.customerHome,
      );

      final approved = SessionState.authenticated(
        _driver(DriverStatus.approved),
      );
      for (final route in [
        AppRoutes.driverSettings,
        AppRoutes.driverEditProfile,
        AppRoutes.driverChangePassword,
      ]) {
        expect(resolveRedirect(approved, route), isNull, reason: route);
      }
      expect(
        resolveRedirect(approved, AppRoutes.customerSavedPlaces),
        AppRoutes.driverHome,
      );

      final pending = SessionState.authenticated(
        _driver(DriverStatus.underReview),
      );
      expect(
        resolveRedirect(pending, AppRoutes.driverSettings),
        AppRoutes.driverPendingApproval,
      );
    });
  });

  group('models', () {
    test('ProfileUpdate sends only what changed; removing email sends null', () {
      expect(
        ProfileUpdate(
          firstName: 'Radha',
          dateOfBirth: DateTime(1994, 8, 5),
          gender: Gender.female,
        ).toJson(),
        {'firstName': 'Radha', 'gender': 'female', 'dob': '1994-08-05'},
      );
      expect(const ProfileUpdate(removeEmail: true).toJson(), {'email': null});
      expect(const ProfileUpdate().isEmpty, isTrue);
    });

    test('AppUser reads the date of birth as a calendar day and keeps the driver status', () {
      final user = AppUser.fromJson({
        'id': 'u1',
        'phone': _phone,
        'role': 'DRIVER',
        'status': 'ACTIVE',
        'firstName': 'Ravi',
        'lastName': 'Kumar',
        'gender': 'male',
        'dob': '1990-01-31T00:00:00.000Z',
        'isEmailVerified': true,
        'profileImage': '/users/me/profile-image?v=abc',
      });
      expect(user.dateOfBirth, DateTime(1990, 1, 31));
      expect(user.gender, Gender.male);
      expect(user.initials, 'RK');
      expect(user.isEmailVerified, isTrue);
      final merged = user.withDriverFrom(_driver(DriverStatus.approved));
      expect(merged.driver?.driverStatus, DriverStatus.approved);
      expect(merged.profileImage, '/users/me/profile-image?v=abc');
    });

    test('SavedPlaces reads the rider\'s own places and the remaining allowance', () {
      final saved = SavedPlaces.fromJson({
        'home': null,
        'work': {
          'address': 'Sector 62, Noida',
          'latitude': 28.62,
          'longitude': 77.37,
        },
        'others': [
          {
            'id': 'p1',
            'label': 'Gym',
            'name': null,
            'address': 'Cult Fit, Sector 18',
            'latitude': 28.57,
            'longitude': 77.32,
          },
        ],
        'othersRemaining': 19,
      });
      expect(saved.home, isNull);
      expect(saved.work?.address, 'Sector 62, Noida');
      expect(saved.others.single.label, 'Gym');
      expect(saved.others.single.place.address, 'Cult Fit, Sector 18');
      expect(saved.canAddOther, isTrue);
      // An older server without "others" still parses.
      expect(SavedPlaces.fromJson({'home': null, 'work': null}).others, isEmpty);
    });

    test('the password rule matches the API policy', () {
      expect(validateNewPassword('Password@123'), isNull);
      expect(validateNewPassword('abcdef'), isNull);
      expect(validateNewPassword('123456'), isNull);
      expect(validateNewPassword('Pass1'), isNotNull);
      expect(validateNewPassword('a' * 129), isNotNull);
      expect(validateNewPassword(''), 'Enter a password');
    });
  });

  group('forgot password', () {
    test('code → ticket → new password signs the user in', () async {
      final flow = container.read(passwordResetFlowProvider.notifier);
      await flow.start(_phone);
      await expectLater(flow.verify('000000'), throwsA(isA<ApiException>()));
      expect(container.read(passwordResetFlowProvider).ticket, isNull);
      await flow.verify(_rightCode);
      expect(container.read(passwordResetFlowProvider).ticket, isNotNull);

      await flow.complete('Changed#456');
      expect(auth.resets.single, {
        'token': 'reset-token-0123456789',
        'password': 'Changed#456',
      });
      expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);
      expect(container.read(passwordResetFlowProvider).challenge, isNull);
    });

    testWidgets('an unknown number explains itself and offers sign-up', (
      tester,
    ) async {
      auth.forgotError = _apiError(
        AuthErrorCodes.accountNotFound,
        'No account',
        status: 404,
      );
      await pump(tester, AppRoutes.forgotPassword, {
        AppRoutes.forgotPassword: (state) =>
            const ForgotPasswordScreen(initialPhone: '9876543210'),
        AppRoutes.forgotPasswordVerify: (_) => const ForgotPasswordOtpScreen(),
      });
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(auth.forgotFor, [_phone]);
      expect(find.textContaining('No Tirvona Rides account'), findsOneWidget);
      expect(find.text('Create an account'), findsOneWidget);
    });

    testWidgets('sending the code opens the WhatsApp verification step', (
      tester,
    ) async {
      await pump(tester, AppRoutes.forgotPassword, {
        AppRoutes.forgotPassword: (state) => const ForgotPasswordScreen(),
        AppRoutes.forgotPasswordVerify: (_) => const ForgotPasswordOtpScreen(),
        AppRoutes.forgotPasswordNew: (_) => const ResetPasswordScreen(),
      });
      await tester.enterText(find.byType(TextFormField), '98765 43210');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the reset code'), findsOneWidget);

      await tester.enterText(find.byType(TextField), _rightCode);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Code verified'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Choose a new password'), findsOneWidget);

      // Mismatched confirmation never reaches the server.
      await tester.enterText(find.byType(TextFormField).at(0), 'Changed#456');
      await tester.enterText(find.byType(TextFormField).at(1), 'Changed#457');
      await tester.tap(find.text('Reset password'));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(auth.resets, isEmpty);

      await tester.enterText(find.byType(TextFormField).at(1), 'Changed#456');
      await tester.tap(find.text('Reset password'));
      await tester.pumpAndSettle();
      expect(auth.resets.single['password'], 'Changed#456');
    });

    testWidgets('an expired reset offers to start again', (tester) async {
      final flow = container.read(passwordResetFlowProvider.notifier);
      await flow.start(_phone);
      await flow.verify(_rightCode);
      auth.resetError = _apiError(
        AuthErrorCodes.passwordResetInvalid,
        'expired',
      );
      await pump(tester, AppRoutes.forgotPasswordNew, {
        AppRoutes.forgotPassword: (_) => const ForgotPasswordScreen(),
        AppRoutes.forgotPasswordNew: (_) => const ResetPasswordScreen(),
      });
      await tester.enterText(find.byType(TextFormField).at(0), 'Changed#456');
      await tester.enterText(find.byType(TextFormField).at(1), 'Changed#456');
      await tester.tap(find.text('Reset password'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This reset has expired'), findsOneWidget);
      await tester.tap(find.text('Request a new code'));
      await tester.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);
    });
  });

  group('account screens', () {
    testWidgets('edit profile sends only the changed name and keeps the driver status', (
      tester,
    ) async {
      await signIn(_driver(DriverStatus.approved));
      await pushOver(tester, '/edit', const EditProfileScreen());
      await tester.enterText(find.byType(TextFormField).first, 'Ravinder');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(account.updates, [
        {'firstName': 'Ravinder'},
      ]);
      final user = container.read(sessionControllerProvider).user!;
      expect(user.firstName, 'Ravinder');
      expect(user.driver?.driverStatus, DriverStatus.approved);
    });

    testWidgets('edit profile rejects an empty first name and a bad email', (
      tester,
    ) async {
      await signIn(_customer);
      await pump(tester, '/edit', {'/edit': (_) => const EditProfileScreen()});
      await tester.enterText(find.byType(TextFormField).at(0), ' ');
      await tester.enterText(find.byType(TextFormField).at(2), 'not-an-email');
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(find.text('Enter your first name'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(account.updates, isEmpty);
    });

    testWidgets('change password maps a wrong current password to plain words', (
      tester,
    ) async {
      await signIn(_customer);
      account.passwordError = _apiError(
        AuthErrorCodes.invalidCredentials,
        'Current password is incorrect',
      );
      await pushOver(tester, '/password', const ChangePasswordScreen());
      await tester.enterText(find.byType(TextFormField).at(0), 'Old@12345');
      await tester.enterText(find.byType(TextFormField).at(1), 'Changed#456');
      await tester.enterText(find.byType(TextFormField).at(2), 'Changed#456');
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(find.text('Your current password is not correct.'), findsOneWidget);

      account.passwordError = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(account.passwordChanges.single, {
        'current': 'Old@12345',
        'new': 'Changed#456',
      });
      expect(find.text('home'), findsOneWidget);
    });

    test('sign out everywhere clears this device after the server agrees', () async {
      await signIn(_customer);
      await container.read(sessionControllerProvider.notifier).logoutEverywhere();
      expect(auth.logoutEverywhereCalls, 1);
      expect(container.read(sessionControllerProvider).isAuthenticated, isFalse);
    });
  });
}
