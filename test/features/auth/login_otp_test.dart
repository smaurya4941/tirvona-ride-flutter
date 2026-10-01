import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tirvona_ride/app/router/app_router.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/core/network/api_exception.dart';
import 'package:tirvona_ride/core/storage/secure_storage.dart';
import 'package:tirvona_ride/features/auth/data/auth_repository.dart';
import 'package:tirvona_ride/features/auth/domain/app_user.dart';
import 'package:tirvona_ride/features/auth/domain/auth_session.dart';
import 'package:tirvona_ride/features/auth/domain/otp_challenge.dart';
import 'package:tirvona_ride/features/auth/presentation/auth_error_messages.dart';
import 'package:tirvona_ride/features/auth/presentation/login_otp_flow.dart';
import 'package:tirvona_ride/features/auth/presentation/login_otp_screen.dart';
import 'package:tirvona_ride/features/auth/presentation/login_screen.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';

const _phone = '+919876543210';
const _rightCode = '123456';

OtpChallenge _challenge({int resendIn = 60, bool codeSent = true}) =>
    OtpChallenge.fromJson({
      'phone': _phone,
      'maskedPhone': '+91 ***** *3210',
      'channel': 'WHATSAPP',
      'codeLength': 6,
      'expiresInSeconds': 300,
      'resendAvailableInSeconds': resendIn,
      'sendsRemaining': 4,
      'codeSent': codeSent,
    });

ApiException _apiError(
  String code,
  String message, {
  int status = 400,
  Object? data,
}) => ApiException(
  kind: ApiErrorKind.client,
  statusCode: status,
  code: code,
  message: message,
  data: data,
);

const _session = AuthSession(
  user: AppUser(
    id: 'u1',
    phone: _phone,
    role: UserRole.customer,
    status: UserStatus.active,
    firstName: 'Ravi',
    isPhoneVerified: true,
  ),
  accessToken: 'access',
  refreshToken: 'refresh',
);

class _FakeAuth extends AuthRepository {
  _FakeAuth() : super(Dio());

  final requested = <String>[];
  final verified = <String>[];
  final passwordLogins = <String>[];
  ApiException? requestError;
  int resendIn = 60;
  bool keepEarlierCode = false;

  @override
  Future<OtpChallenge> requestLoginOtp(String phone) async {
    requested.add(phone);
    final error = requestError;
    if (error != null) throw error;
    final keep = keepEarlierCode && requested.length > 1;
    return _challenge(resendIn: resendIn, codeSent: !keep);
  }

  @override
  Future<AuthSession> verifyLoginOtp({
    required String phone,
    required String otp,
    required String deviceId,
  }) async {
    verified.add(otp);
    if (otp != _rightCode) {
      throw _apiError(
        AuthErrorCodes.otpInvalid,
        'Incorrect verification code',
        data: {'attemptsRemaining': 4},
      );
    }
    return _session;
  }

  @override
  Future<AuthSession> login({
    required String phone,
    required String password,
    required String deviceId,
  }) async {
    passwordLogins.add(phone);
    return _session;
  }
}

void main() {
  late _FakeAuth auth;
  late ProviderContainer container;

  ProviderContainer newContainer() => ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    auth = _FakeAuth();
    container = newContainer();
  });

  tearDown(() => container.dispose());

  /// Login and code screens, as the app wires them (guests only).
  Future<void> pumpLogin(
    WidgetTester tester, {
    String initialLocation = AppRoutes.login,
  }) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: AppRoutes.loginVerify,
          builder: (context, state) => const LoginOtpScreen(),
        ),
        GoRoute(
          path: AppRoutes.register,
          builder: (context, state) =>
              const Scaffold(body: Text('signup form')),
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
  }

  Future<void> chooseWhatsApp(WidgetTester tester) async {
    await tester.tap(find.text('WhatsApp code'));
    await tester.pump();
  }

  Future<void> sendCode(
    WidgetTester tester, {
    String phone = '9876543210',
  }) async {
    await tester.enterText(find.byType(TextFormField).first, phone);
    await tester.tap(find.text('Send code on WhatsApp'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('LoginScreen method toggle', () {
    testWidgets('password mode is the default and works as before', (
      tester,
    ) async {
      await pumpLogin(tester);
      expect(find.text('Password'), findsWidgets);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), '98765 43210');
      await tester.enterText(find.byType(TextFormField).at(1), 'Password@123');
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(auth.passwordLogins, [_phone]);
      expect(auth.requested, isEmpty);
      expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);
    });

    testWidgets('WhatsApp mode hides the password and sends a code', (
      tester,
    ) async {
      await pumpLogin(tester);
      await chooseWhatsApp(tester);

      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Forgot password?'), findsNothing);
      expect(find.text('Send code on WhatsApp'), findsOneWidget);

      // The number is validated before anything is sent.
      await sendCode(tester, phone: '12345');
      expect(auth.requested, isEmpty);
    });

    testWidgets('the toggle stores the choice on the device', (tester) async {
      await pumpLogin(tester);
      await chooseWhatsApp(tester);
      await tester.pump();
      expect(
        container.read(loginMethodPreferenceProvider),
        LoginMethod.whatsappOtp,
      );
      expect(
        await tester.runAsync(() => SecureStorage().read('auth.loginMethod')),
        LoginMethod.whatsappOtp.name,
      );
    });

    test('a fresh start opens on the method chosen last time', () async {
      await SecureStorage().write('auth.loginMethod', 'whatsappOtp');
      final next = newContainer();
      addTearDown(next.dispose);
      expect(next.read(loginMethodPreferenceProvider), LoginMethod.password);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(next.read(loginMethodPreferenceProvider), LoginMethod.whatsappOtp);
    });

    test('a choice made before the stored one loads wins', () async {
      await SecureStorage().write('auth.loginMethod', 'whatsappOtp');
      final next = newContainer();
      addTearDown(next.dispose);
      next.read(loginMethodPreferenceProvider);
      await next
          .read(loginMethodPreferenceProvider.notifier)
          .choose(LoginMethod.password);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(next.read(loginMethodPreferenceProvider), LoginMethod.password);
      expect(await SecureStorage().read('auth.loginMethod'), 'password');
    });
  });

  group('Login with a WhatsApp code', () {
    testWidgets('send code → code screen → signed in', (tester) async {
      await pumpLogin(tester);
      await chooseWhatsApp(tester);
      await sendCode(tester, phone: '098765 43210');

      expect(auth.requested, [_phone]);
      expect(find.text('Enter your sign-in code'), findsOneWidget);
      expect(find.textContaining('+91 98765 43210'), findsOneWidget);
      expect(find.textContaining('Resend available in'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '000000');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text("That code isn't right. 4 attempts left."),
        findsOneWidget,
      );
      expect(
        container.read(sessionControllerProvider).isAuthenticated,
        isFalse,
      );

      await tester.enterText(find.byType(TextField), _rightCode);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Signed in'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));

      expect(auth.verified, ['000000', _rightCode]);
      expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);
      expect(await SecureStorage().readRefreshToken(), 'refresh');
      expect(container.read(loginOtpFlowProvider), isNull);
    });

    testWidgets('an unknown number offers sign-up instead', (tester) async {
      auth.requestError = _apiError(
        AuthErrorCodes.accountNotFound,
        'No Tirvona Rides account uses this mobile number.',
        status: 404,
      );
      await pumpLogin(tester);
      await chooseWhatsApp(tester);
      await sendCode(tester);

      expect(find.textContaining('No Tirvona Rides account'), findsOneWidget);
      expect(find.text('Enter your sign-in code'), findsNothing);
      await tester.tap(find.text('Create an account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('signup form'), findsOneWidget);
    });

    testWidgets('a blocked account sees why, with no sign-up offer', (
      tester,
    ) async {
      auth.requestError = _apiError(
        AuthErrorCodes.userBlocked,
        'This account has been blocked',
        status: 403,
      );
      await pumpLogin(tester);
      await chooseWhatsApp(tester);
      await sendCode(tester);

      expect(find.textContaining('has been blocked'), findsOneWidget);
      expect(find.text('Create an account'), findsNothing);
    });

    testWidgets('resend asks the server again; a kept code is not "new"', (
      tester,
    ) async {
      auth
        ..resendIn = 0
        ..keepEarlierCode = true;
      await pumpLogin(tester);
      await chooseWhatsApp(tester);
      await sendCode(tester);

      await tester.tap(find.text('Resend code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(auth.requested, [_phone, _phone]);
      expect(
        find.textContaining('We sent you a code a moment ago'),
        findsOneWidget,
      );
      expect(find.textContaining('New code sent'), findsNothing);
    });

    testWidgets('without a code on its way it leads back to sign in', (
      tester,
    ) async {
      await pumpLogin(tester, initialLocation: AppRoutes.loginVerify);
      expect(
        find.text('There is no sign-in waiting for a code.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Back to sign in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Welcome back'), findsOneWidget);
    });
  });

  group('redirects for /login/verify', () {
    const customer = AppUser(
      id: 'u1',
      phone: _phone,
      role: UserRole.customer,
      status: UserStatus.active,
      firstName: 'Ravi',
      isPhoneVerified: true,
    );

    test('is reachable while signed out', () {
      expect(
        resolveRedirect(
          const SessionState.unauthenticated(),
          AppRoutes.loginVerify,
        ),
        isNull,
      );
    });

    test('leaves for the role home once signed in', () {
      expect(
        resolveRedirect(
          const SessionState.authenticated(customer),
          AppRoutes.loginVerify,
        ),
        AppRoutes.customerHome,
      );
      const driver = AppUser(
        id: 'u2',
        phone: _phone,
        role: UserRole.driver,
        status: UserStatus.active,
        firstName: 'Ravi',
        isPhoneVerified: true,
        driver: DriverStatusInfo(driverStatus: DriverStatus.approved),
      );
      expect(
        resolveRedirect(
          const SessionState.authenticated(driver),
          AppRoutes.loginVerify,
        ),
        AppRoutes.driverHome,
      );
    });

    test('waits on splash while the session is restoring', () {
      expect(
        resolveRedirect(const SessionState.unknown(), AppRoutes.loginVerify),
        AppRoutes.splash,
      );
    });
  });
}
