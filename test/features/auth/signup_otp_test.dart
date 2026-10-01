import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/core/network/api_exception.dart';
import 'package:tirvona_ride/features/auth/data/auth_repository.dart';
import 'package:tirvona_ride/features/auth/domain/app_user.dart';
import 'package:tirvona_ride/features/auth/domain/auth_session.dart';
import 'package:tirvona_ride/features/auth/domain/otp_challenge.dart';
import 'package:tirvona_ride/features/auth/presentation/auth_error_messages.dart';
import 'package:tirvona_ride/features/auth/presentation/phone_utils.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';
import 'package:tirvona_ride/features/auth/presentation/signup_flow.dart';
import 'package:tirvona_ride/features/auth/presentation/signup_otp_screen.dart';

const _phone = '+919876543210';
const _rightCode = '123456';

OtpChallenge _challenge({int resendIn = 60, bool codeSent = true}) =>
    OtpChallenge.fromJson({
      'verificationId': 'verification-id-0123456789',
      'phone': _phone,
      'maskedPhone': '+91 ***** *3210',
      'channel': 'WHATSAPP',
      'codeLength': 6,
      'expiresInSeconds': 300,
      'resendAvailableInSeconds': resendIn,
      'sendsRemaining': 4,
      'codeSent': codeSent,
    });

ApiException _apiError(String code, String message, {Object? data}) =>
    ApiException(
      kind: ApiErrorKind.client,
      statusCode: 400,
      code: code,
      message: message,
      data: data,
    );

class _FakeAuth extends AuthRepository {
  _FakeAuth() : super(Dio());

  final verified = <String>[];
  int resends = 0;
  int registerResendIn = 60;
  ApiException? verifyError;
  final registered = <Map<String, Object?>>[];

  @override
  Future<OtpChallenge> register({
    required String firstName,
    String? lastName,
    required String phone,
    String? email,
    required String password,
    required UserRole role,
  }) async {
    registered.add({'phone': phone, 'role': role});
    return _challenge(resendIn: registerResendIn);
  }

  @override
  Future<AuthSession> verifySignupOtp({
    required String phone,
    required String verificationId,
    required String otp,
    required String deviceId,
  }) async {
    verified.add(otp);
    final error = verifyError;
    if (error != null) throw error;
    if (otp != _rightCode) {
      throw _apiError(
        AuthErrorCodes.otpInvalid,
        'Incorrect verification code',
        data: {'attemptsRemaining': 4},
      );
    }
    return const AuthSession(
      user: AppUser(
        id: 'u1',
        phone: _phone,
        role: UserRole.customer,
        status: UserStatus.active,
        firstName: 'Asha',
        isPhoneVerified: true,
      ),
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }

  @override
  Future<OtpChallenge> resendSignupOtp({
    required String phone,
    required String verificationId,
  }) async {
    resends++;
    return _challenge();
  }
}

void main() {
  late _FakeAuth auth;
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    auth = _FakeAuth();
    container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
    );
  });

  tearDown(() => container.dispose());

  Future<void> startSignup() => container
      .read(signupFlowProvider.notifier)
      .start(
        firstName: 'Asha',
        phone: _phone,
        password: 'Password@123',
        role: UserRole.customer,
      );

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRoutes.registerVerify,
      routes: [
        GoRoute(
          path: AppRoutes.register,
          builder: (context, state) =>
              const Scaffold(body: Text('signup form')),
        ),
        GoRoute(
          path: AppRoutes.registerVerify,
          builder: (context, state) => const SignupOtpScreen(),
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

  group('SignupOtpScreen', () {
    testWidgets('shows the WhatsApp number and a server-driven resend timer', (
      tester,
    ) async {
      await startSignup();
      await pumpScreen(tester);

      expect(find.text('Verify your phone'), findsOneWidget);
      expect(find.textContaining('on WhatsApp to'), findsOneWidget);
      expect(find.textContaining('+91 98765 43210'), findsOneWidget);
      expect(find.textContaining('Resend available in'), findsOneWidget);
      expect(find.textContaining('Code expires in 4:'), findsOneWidget);
    });

    testWidgets('a wrong code shows attempts left; the right one signs in', (
      tester,
    ) async {
      await startSignup();
      await pumpScreen(tester);

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
      expect(find.text('Phone verified'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));

      expect(auth.verified, ['000000', _rightCode]);
      final session = container.read(sessionControllerProvider);
      expect(session.isAuthenticated, isTrue);
      expect(session.user!.isPhoneVerified, isTrue);
      expect(container.read(signupFlowProvider), isNull);
    });

    testWidgets('resend is offered once the timer ends', (tester) async {
      auth.registerResendIn = 0;
      await startSignup();
      await pumpScreen(tester);

      await tester.tap(find.text('Resend code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(auth.resends, 1);
      expect(find.textContaining('New code sent on WhatsApp'), findsOneWidget);
      expect(find.textContaining('Resend available in'), findsOneWidget);
    });

    testWidgets('an expired sign-up sends the user back to the form', (
      tester,
    ) async {
      await startSignup();
      auth.verifyError = _apiError(
        AuthErrorCodes.signupSessionInvalid,
        'This sign-up has expired or was replaced.',
      );
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), _rightCode);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Sign-up expired'), findsOneWidget);

      await tester.tap(find.text('Back to sign-up'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('signup form'), findsOneWidget);
      expect(container.read(signupFlowProvider), isNull);
    });

    testWidgets('without a pending sign-up it offers to start one', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Start sign-up'), findsOneWidget);
    });
  });

  group('phone utils', () {
    test('normalises Indian numbers however they are typed', () {
      for (final input in [
        '9876543210',
        '98765 43210',
        '098765-43210',
        '919876543210',
        '+91 98765 43210',
      ]) {
        expect(normalizePhone(input), _phone, reason: input);
      }
    });

    test('accepts only reachable mobiles', () {
      expect(validatePhone('98765 43210'), isNull);
      expect(validatePhone('1123456789'), isNotNull);
      expect(validatePhone('12345'), isNotNull);
      expect(validatePhone(''), 'Enter your mobile number');
    });

    test('formats for display', () {
      expect(formatPhoneForDisplay(_phone), '+91 98765 43210');
      expect(formatPhoneForDisplay('+14155550123'), '+14155550123');
    });
  });

  group('auth error messages', () {
    test('explain OTP failures in plain words', () {
      expect(
        _apiError(
          AuthErrorCodes.otpInvalid,
          'x',
          data: {'attemptsRemaining': 1},
        ).authMessage,
        "That code isn't right. 1 attempt left.",
      );
      expect(_apiError(AuthErrorCodes.otpExpired, 'x').needsNewCode, isTrue);
      expect(
        _apiError(
          AuthErrorCodes.otpResendTooSoon,
          'Please wait 42s',
          data: {'retryAfterSeconds': 42},
        ).retryAfter,
        const Duration(seconds: 42),
      );
      // Unknown codes fall back to the server's own (safe) message.
      expect(
        _apiError('SOMETHING_NEW', 'Server says').authMessage,
        'Server says',
      );
    });
  });

  test('OtpChallenge anchors server timers to the device clock', () {
    final received = DateTime(2026, 9, 29, 10);
    final challenge = OtpChallenge.fromJson({
      'phone': _phone,
      'expiresInSeconds': 300,
      'resendAvailableInSeconds': 60,
      'sendsRemaining': 3,
      'codeSent': false,
    }, receivedAt: received);
    expect(challenge.expiresAt, received.add(const Duration(minutes: 5)));
    expect(
      challenge.resendAvailableAt,
      received.add(const Duration(minutes: 1)),
    );
    expect(challenge.verificationId, isNull);
    expect(challenge.codeLength, 6);
    expect(challenge.codeSent, isFalse);
  });
}
