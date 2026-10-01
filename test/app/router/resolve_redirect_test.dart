import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/app/router/app_router.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/features/auth/domain/app_user.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';

AppUser _user(
  UserRole role, {
  bool phoneVerified = true,
  DriverStatus? driverStatus,
}) => AppUser(
  id: 'u1',
  phone: '+919812345678',
  role: role,
  status: UserStatus.active,
  firstName: 'Test',
  isPhoneVerified: phoneVerified,
  driver: driverStatus == null
      ? null
      : DriverStatusInfo(driverStatus: driverStatus),
);

SessionState _signedIn(AppUser user) => SessionState.authenticated(user);

void main() {
  group('resolveRedirect', () {
    test('Phase 4 — customers reach payment and receipt screens', () {
      final session = _signedIn(_user(UserRole.customer));
      expect(
        resolveRedirect(session, AppRoutes.customerRidePayment('r1')),
        isNull,
      );
      expect(resolveRedirect(session, AppRoutes.customerPayment('p1')), isNull);
      expect(
        resolveRedirect(session, AppRoutes.driverEarning('e1')),
        AppRoutes.customerHome,
      );
    });

    test('holds on splash while the session is restoring', () {
      const session = SessionState.unknown();
      expect(resolveRedirect(session, AppRoutes.splash), isNull);
      expect(resolveRedirect(session, AppRoutes.login), AppRoutes.splash);
    });

    test('keeps the splash up during its minimum display time', () {
      const signedOut = SessionState.unauthenticated();
      final customer = _signedIn(_user(UserRole.customer));
      expect(
        resolveRedirect(signedOut, AppRoutes.splash, holdSplash: true),
        isNull,
      );
      expect(
        resolveRedirect(customer, AppRoutes.splash, holdSplash: true),
        isNull,
      );
      // The hold never pins any other route (deep links, push taps).
      expect(
        resolveRedirect(customer, AppRoutes.login, holdSplash: true),
        AppRoutes.customerHome,
      );
      expect(
        resolveRedirect(customer, AppRoutes.splash),
        AppRoutes.customerHome,
      );
    });

    test('sends signed-out users to login but lets them register', () {
      const session = SessionState.unauthenticated();
      expect(resolveRedirect(session, AppRoutes.splash), AppRoutes.login);
      expect(resolveRedirect(session, AppRoutes.customerHome), AppRoutes.login);
      expect(resolveRedirect(session, AppRoutes.register), isNull);
      // Signup step 2 happens before any account exists.
      expect(resolveRedirect(session, AppRoutes.registerVerify), isNull);
    });

    test('a verified signup leaves the OTP step for its role', () {
      final customer = _signedIn(_user(UserRole.customer));
      expect(
        resolveRedirect(customer, AppRoutes.registerVerify),
        AppRoutes.customerHome,
      );
      final driver = _signedIn(
        _user(UserRole.driver, driverStatus: DriverStatus.pending),
      );
      expect(
        resolveRedirect(driver, AppRoutes.registerVerify),
        AppRoutes.driverRegistration,
      );
    });

    test('forces phone verification before any shell', () {
      final session = _signedIn(_user(UserRole.customer, phoneVerified: false));
      expect(resolveRedirect(session, AppRoutes.customerHome), AppRoutes.otp);
      expect(resolveRedirect(session, AppRoutes.otp), isNull);
    });

    test('Test A — a customer lands on the customer shell', () {
      final session = _signedIn(_user(UserRole.customer));
      expect(resolveRedirect(session, AppRoutes.login), AppRoutes.customerHome);
      expect(resolveRedirect(session, AppRoutes.otp), AppRoutes.customerHome);
      expect(resolveRedirect(session, AppRoutes.customerHome), isNull);
      expect(
        resolveRedirect(session, AppRoutes.driverHome),
        AppRoutes.customerHome,
      );
    });

    test('Test B — a pending driver is kept in onboarding', () {
      final session = _signedIn(
        _user(UserRole.driver, driverStatus: DriverStatus.pending),
      );
      expect(
        resolveRedirect(session, AppRoutes.otp),
        AppRoutes.driverRegistration,
      );
      expect(resolveRedirect(session, AppRoutes.driverVehicle), isNull);
      expect(resolveRedirect(session, AppRoutes.driverKyc), isNull);
      expect(
        resolveRedirect(session, AppRoutes.driverHome),
        AppRoutes.driverRegistration,
      );
    });

    test('Test B — a driver under review only sees pending approval', () {
      final session = _signedIn(
        _user(UserRole.driver, driverStatus: DriverStatus.underReview),
      );
      expect(
        resolveRedirect(session, AppRoutes.driverKyc),
        AppRoutes.driverPendingApproval,
      );
      expect(
        resolveRedirect(session, AppRoutes.driverHome),
        AppRoutes.driverPendingApproval,
      );
      expect(resolveRedirect(session, AppRoutes.driverPendingApproval), isNull);
    });

    test('a rejected driver may edit and resubmit', () {
      final session = _signedIn(
        _user(UserRole.driver, driverStatus: DriverStatus.rejected),
      );
      expect(
        resolveRedirect(session, AppRoutes.login),
        AppRoutes.driverPendingApproval,
      );
      expect(resolveRedirect(session, AppRoutes.driverRegistration), isNull);
      expect(
        resolveRedirect(session, AppRoutes.driverHome),
        AppRoutes.driverPendingApproval,
      );
    });

    test('Test D — an approved driver lands on the driver shell', () {
      final session = _signedIn(
        _user(UserRole.driver, driverStatus: DriverStatus.approved),
      );
      expect(resolveRedirect(session, AppRoutes.login), AppRoutes.driverHome);
      expect(
        resolveRedirect(session, AppRoutes.driverPendingApproval),
        AppRoutes.driverHome,
      );
      expect(resolveRedirect(session, AppRoutes.driverHome), isNull);
    });

    test('Phase 2 — customers reach booking and ride screens only', () {
      final session = _signedIn(_user(UserRole.customer));
      for (final location in [
        AppRoutes.customerRideOptions,
        AppRoutes.customerRide('66f0c0ffee0000000000abcd'),
      ]) {
        expect(resolveRedirect(session, location), isNull, reason: location);
      }
      expect(
        resolveRedirect(session, AppRoutes.driverRide('x')),
        AppRoutes.customerHome,
      );
      // A prefix match must not let '/customerX' through.
      expect(resolveRedirect(session, '/customers'), AppRoutes.customerHome);
    });

    test('Phase 2 — approved drivers reach ride screens, not onboarding', () {
      final session = _signedIn(
        _user(UserRole.driver, driverStatus: DriverStatus.approved),
      );
      expect(resolveRedirect(session, AppRoutes.driverRide('abc')), isNull);
      expect(resolveRedirect(session, AppRoutes.driverEarning('e1')), isNull);
      expect(
        resolveRedirect(session, AppRoutes.customerPayment('p1')),
        AppRoutes.driverHome,
      );
      expect(
        resolveRedirect(session, AppRoutes.driverRegistration),
        AppRoutes.driverHome,
      );
      expect(
        resolveRedirect(session, AppRoutes.customerRide('abc')),
        AppRoutes.driverHome,
      );
    });

    test('Phase 2 — unapproved drivers cannot open ride screens', () {
      final session = _signedIn(
        _user(UserRole.driver, driverStatus: DriverStatus.underReview),
      );
      expect(
        resolveRedirect(session, AppRoutes.driverRide('abc')),
        AppRoutes.driverPendingApproval,
      );
    });

    test('admins are told to use the web panel', () {
      final session = _signedIn(_user(UserRole.admin, phoneVerified: false));
      expect(
        resolveRedirect(session, AppRoutes.customerHome),
        AppRoutes.adminUnsupported,
      );
    });

    test('system status is reachable from any state', () {
      expect(
        resolveRedirect(const SessionState.unknown(), AppRoutes.systemStatus),
        isNull,
      );
      expect(
        resolveRedirect(
          const SessionState.unauthenticated(),
          AppRoutes.systemStatus,
        ),
        isNull,
      );
    });
  });

  group('AppUser.fromJson', () {
    test('parses the /auth/me driver payload', () {
      final user = AppUser.fromJson({
        'id': 'abc',
        'phone': '+919812345678',
        'role': 'DRIVER',
        'status': 'ACTIVE',
        'firstName': 'Rahul',
        'lastName': 'Kumar',
        'isPhoneVerified': true,
        'driver': {'driverStatus': 'UNDER_REVIEW'},
      });
      expect(user.role, UserRole.driver);
      expect(user.driver?.driverStatus, DriverStatus.underReview);
      expect(user.displayName, 'Rahul Kumar');
    });
  });
}
