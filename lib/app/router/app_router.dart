import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/change_password_screen.dart';
import '../../features/account/presentation/edit_profile_screen.dart';
import '../../features/account/presentation/settings_screen.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/admin_unsupported_screen.dart';
import '../../features/auth/presentation/forgot_password_screens.dart';
import '../../features/auth/presentation/login_otp_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/auth/presentation/signup_otp_screen.dart';
import '../../features/auth/presentation/splash_hold.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/complaints/screens/support_screens.dart';
import '../../features/customer/circuit/circuit_booking_screen.dart';
import '../../features/customer/circuit/circuit_details_screen.dart';
import '../../features/customer/circuit/circuit_list_screen.dart';
import '../../features/customer/payments/screens/payment_receipt_screen.dart';
import '../../features/customer/payments/screens/ride_payment_screen.dart';
import '../../features/customer/presentation/customer_shell.dart';
import '../../features/customer/rating/screens/rate_driver_screen.dart';
import '../../features/driver/account/presentation/driver_details_screen.dart';
import '../../features/driver/account/presentation/driver_documents_screen.dart';
import '../../features/driver/account/presentation/driver_reviews_screen.dart';
import '../../features/driver/account/presentation/driver_vehicle_screen.dart';
import '../../features/driver/earnings/screens/earning_detail_screen.dart';
import '../../features/driver/presentation/driver_registration_screen.dart';
import '../../features/driver/presentation/driver_shell.dart';
import '../../features/driver/presentation/kyc_documents_screen.dart';
import '../../features/driver/presentation/pending_approval_screen.dart';
import '../../features/driver/presentation/vehicle_details_screen.dart';
import '../../features/notifications/screens/notification_center_screen.dart';
import '../../features/places/application/popular_places.dart';
import '../../features/places/domain/saved_place.dart';
import '../../features/places/presentation/location_search_screen.dart';
import '../../features/places/presentation/map_location_picker_screen.dart';
import '../../features/places/presentation/saved_places_screen.dart';
import '../../features/rides/presentation/customer/ride_options_screen.dart';
import '../../features/rides/presentation/customer/ride_tracking_screen.dart';
import '../../features/rides/presentation/driver/driver_ride_screen.dart';
import '../../features/safety/screens/emergency_contacts_screen.dart';
import '../../features/system/presentation/map_check_screen.dart';
import '../../features/system/presentation/system_status_screen.dart';
import 'app_routes.dart';

const _guestRoutes = {
  AppRoutes.login,
  AppRoutes.loginVerify,
  AppRoutes.register,
  AppRoutes.registerVerify,
  AppRoutes.forgotPassword,
  AppRoutes.forgotPasswordVerify,
  AppRoutes.forgotPasswordNew,
};
const _driverOnboardingRoutes = {
  AppRoutes.driverRegistration,
  AppRoutes.driverVehicle,
  AppRoutes.driverKyc,
};

/// Decides where a session may be, given the current location. Returns the
/// location to redirect to, or `null` to stay. Kept as a pure function so
/// the whole matrix is unit-testable without a widget tree. While
/// [holdSplash] is set (the splash's minimum display time) the splash route
/// is kept even if the session has already resolved.
@visibleForTesting
String? resolveRedirect(
  SessionState session,
  String location, {
  bool holdSplash = false,
}) {
  if (holdSplash && location == AppRoutes.splash) return null;

  // Diagnostics stay reachable from every state.
  if (location == AppRoutes.systemStatus ||
      location == AppRoutes.systemMapCheck) {
    return null;
  }

  switch (session.status) {
    case SessionStatus.unknown:
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    case SessionStatus.unauthenticated:
      return _guestRoutes.contains(location) ? null : AppRoutes.login;
    case SessionStatus.authenticated:
      break;
  }

  final user = session.user!;
  if (!user.isPhoneVerified && user.role != UserRole.admin) {
    return location == AppRoutes.otp ? null : AppRoutes.otp;
  }

  final String home;
  final Set<String> allowed;
  // Sub-trees a role may enter (ride screens carry ids in the path).
  var allowedPrefixes = const <String>{};
  switch (user.role) {
    case UserRole.admin:
      home = AppRoutes.adminUnsupported;
      allowed = {AppRoutes.adminUnsupported};
    case UserRole.customer:
      home = AppRoutes.customerHome;
      allowed = {AppRoutes.customerHome};
      allowedPrefixes = {'${AppRoutes.customerHome}/'};
    case UserRole.driver:
      final status = user.driver?.driverStatus ?? DriverStatus.pending;
      switch (status) {
        case DriverStatus.approved:
          home = AppRoutes.driverHome;
          allowed = {
            AppRoutes.driverHome,
            AppRoutes.driverNotifications,
            AppRoutes.driverEmergencyContacts,
            AppRoutes.driverSupport,
            AppRoutes.driverSettings,
          };
          allowedPrefixes = {
            '${AppRoutes.driverHome}/rides/',
            '${AppRoutes.driverHome}/earnings/',
            '${AppRoutes.driverSupport}/',
            '${AppRoutes.driverSettings}/',
            '${AppRoutes.driverAccount}/',
          };
        case DriverStatus.pending:
          home = AppRoutes.driverRegistration;
          allowed = _driverOnboardingRoutes;
        case DriverStatus.rejected:
          // Rejected drivers see why, then may edit and resubmit.
          home = AppRoutes.driverPendingApproval;
          allowed = {
            AppRoutes.driverPendingApproval,
            ..._driverOnboardingRoutes,
          };
        case DriverStatus.underReview || DriverStatus.suspended:
          home = AppRoutes.driverPendingApproval;
          allowed = {AppRoutes.driverPendingApproval};
      }
  }
  final isAllowed =
      allowed.contains(location) ||
      allowedPrefixes.any((prefix) => location.startsWith(prefix));
  return isAllowed ? null : home;
}

/// Global navigator key for top-level overlays (such as heads-up notification banners).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Built once. Session changes (login, logout, OTP verification, KYC
/// submission, approval) and the end of the splash hold bump [refresh],
/// which makes GoRouter re-run the redirect against the latest session
/// without losing the navigation stack.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(sessionControllerProvider, (_, _) => refresh.value++)
    ..listen(splashHoldProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(
      ref.read(sessionControllerProvider),
      state.matchedLocation,
      holdSplash: ref.read(splashHoldProvider),
    ),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.systemStatus,
        builder: (context, state) => const SystemStatusScreen(),
      ),
      GoRoute(
        path: AppRoutes.systemMapCheck,
        builder: (context, state) => const MapCheckScreen(),
      ),
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
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => ForgotPasswordScreen(
          initialPhone: state.uri.queryParameters['phone'],
        ),
      ),
      GoRoute(
        path: AppRoutes.forgotPasswordVerify,
        builder: (context, state) => const ForgotPasswordOtpScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPasswordNew,
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      // ── Account (both roles, under the role's own prefix) ──
      GoRoute(
        path: AppRoutes.customerSettings,
        builder: (context, state) => const SettingsScreen(isDriver: false),
      ),
      GoRoute(
        path: AppRoutes.customerEditProfile,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerChangePassword,
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerSavedPlaces,
        builder: (context, state) => const SavedPlacesScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverSettings,
        builder: (context, state) => const SettingsScreen(isDriver: true),
      ),
      GoRoute(
        path: AppRoutes.driverEditProfile,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverChangePassword,
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverDetails,
        builder: (context, state) => const DriverDetailsScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverVehicleDetails,
        builder: (context, state) => const DriverVehicleScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverDocuments,
        builder: (context, state) => const DriverDocumentsScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverReviews,
        builder: (context, state) => const DriverReviewsScreen(),
      ),
      GoRoute(
        path: AppRoutes.registerVerify,
        builder: (context, state) => const SignupOtpScreen(),
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, state) => const OtpScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerHome,
        builder: (context, state) => const CustomerShell(),
      ),
      GoRoute(
        path: AppRoutes.customerPlaceSearch,
        builder: (context, state) => LocationSearchScreen(
          initialField: PlaceField.parse(state.uri.queryParameters['field']),
          saveAs: SavedPlaceKind.tryParse(state.uri.queryParameters['saveAs']),
          pickOnly: state.uri.queryParameters['mode'] == 'pick',
        ),
      ),
      GoRoute(
        path: AppRoutes.customerMapPicker,
        builder: (context, state) => MapLocationPickerScreen(
          field: PlaceField.parse(state.uri.queryParameters['field']),
        ),
      ),
      GoRoute(
        path: AppRoutes.customerRideOptions,
        builder: (context, state) => const RideOptionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerCircuits,
        builder: (context, state) => const CircuitListScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerCircuitBookPattern,
        builder: (context, state) =>
            CircuitBookingScreen(packageId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.customerCircuitPattern,
        builder: (context, state) =>
            CircuitDetailsScreen(packageId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.customerRidePattern,
        builder: (context, state) =>
            RideTrackingScreen(rideId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.customerRidePaymentPattern,
        builder: (context, state) =>
            RidePaymentScreen(rideId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.customerRideRatingPattern,
        builder: (context, state) =>
            RateDriverScreen(rideId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.customerPaymentPattern,
        builder: (context, state) =>
            PaymentReceiptScreen(paymentId: state.pathParameters['id']!),
      ),
      // ── Notifications, safety, support (Phase 5), one per role prefix ──
      for (final isDriver in const [false, true]) ...[
        GoRoute(
          path: AppRoutes.notificationsFor(isDriver),
          builder: (context, state) => const NotificationCenterScreen(),
        ),
        GoRoute(
          path: AppRoutes.emergencyContactsFor(isDriver),
          builder: (context, state) => const EmergencyContactsScreen(),
        ),
        GoRoute(
          path: AppRoutes.supportFor(isDriver),
          builder: (context, state) => const SupportScreen(),
        ),
        // Before the ":id" route so "new" is never read as an id.
        GoRoute(
          path: isDriver
              ? AppRoutes.driverSupportNew
              : AppRoutes.customerSupportNew,
          builder: (context, state) =>
              ComplaintFormScreen(rideId: state.uri.queryParameters['rideId']),
        ),
        GoRoute(
          path: isDriver
              ? AppRoutes.driverComplaintPattern
              : AppRoutes.customerComplaintPattern,
          builder: (context, state) =>
              ComplaintDetailScreen(complaintId: state.pathParameters['id']!),
        ),
      ],
      GoRoute(
        path: AppRoutes.driverEarningPattern,
        builder: (context, state) =>
            EarningDetailScreen(earningId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.driverHome,
        builder: (context, state) => const DriverShell(),
      ),
      GoRoute(
        path: AppRoutes.driverRidePattern,
        builder: (context, state) =>
            DriverRideScreen(rideId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.driverRegistration,
        builder: (context, state) => const DriverRegistrationScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverVehicle,
        builder: (context, state) => const VehicleDetailsScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverKyc,
        builder: (context, state) => const KycDocumentsScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverPendingApproval,
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminUnsupported,
        builder: (context, state) => const AdminUnsupportedScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
