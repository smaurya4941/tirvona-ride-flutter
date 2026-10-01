/// Route paths for the whole app. See app_router.dart for the
/// role/driver-status redirect matrix that decides which of these a given
/// session is allowed to land on.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const systemStatus = '/system-status';
  static const systemMapCheck = '/system-status/map';

  static const login = '/login';
  // Login with a WhatsApp code, step 2: the code (a guest route).
  static const loginVerify = '/login/verify';
  static const register = '/register';
  // Signup step 2: the WhatsApp code (a guest route — no account yet).
  static const registerVerify = '/register/verify';
  static const otp = '/otp';
  // Forgot password: number → WhatsApp code → new password (guest routes).
  static const forgotPassword = '/forgot-password';
  static const forgotPasswordVerify = '/forgot-password/verify';
  static const forgotPasswordNew = '/forgot-password/new';
  static String forgotPasswordFor(String phone) =>
      '$forgotPassword?phone=${Uri.encodeQueryComponent(phone)}';

  static const customerHome = '/customer';
  // "Where to?": typed search for pickup/destination, and a map pin.
  static const customerPlaceSearch = '/customer/book/where';
  static String customerPlaceSearchFor(String field) =>
      '$customerPlaceSearch?field=$field';

  /// The same search screen, choosing an address to save as Home or Work.
  static String customerSavePlace(String kind) =>
      '$customerPlaceSearch?field=destination&saveAs=$kind';

  /// The same search screen, only choosing an address and returning it
  /// (e.g. for one of the rider's own saved places).
  static const customerPickAddress =
      '$customerPlaceSearch?field=destination&mode=pick';
  static const customerMapPicker = '/customer/book/pin';
  static String customerMapPickerFor(String field) =>
      '$customerMapPicker?field=$field';
  static const customerRideOptions = '/customer/book/options';
  static const customerRidePattern = '/customer/rides/:id';
  static String customerRide(String id) => '/customer/rides/$id';
  static const customerRidePaymentPattern = '/customer/rides/:id/pay';
  static String customerRidePayment(String id) => '/customer/rides/$id/pay';
  static const customerPaymentPattern = '/customer/payments/:id';
  static String customerPayment(String id) => '/customer/payments/$id';
  static const customerRideRatingPattern = '/customer/rides/:id/rate';
  static String customerRideRating(String id) => '/customer/rides/$id/rate';
  static const customerNotifications = '/customer/notifications';
  static const customerEmergencyContacts = '/customer/emergency-contacts';
  static const customerSupport = '/customer/support';
  static const customerSupportNew = '/customer/support/new';
  static const customerComplaintPattern = '/customer/support/:id';
  static String customerComplaint(String id) => '/customer/support/$id';
  static const customerSavedPlaces = '/customer/saved-places';
  static const customerSettings = '/customer/settings';
  static const customerEditProfile = '/customer/settings/profile';
  static const customerChangePassword = '/customer/settings/password';

  static const driverRegistration = '/driver/registration';
  static const driverVehicle = '/driver/vehicle';
  static const driverKyc = '/driver/kyc';
  static const driverPendingApproval = '/driver/pending-approval';
  static const driverHome = '/driver';
  static const driverRidePattern = '/driver/rides/:id';
  static String driverRide(String id) => '/driver/rides/$id';
  static const driverEarningPattern = '/driver/earnings/:id';
  static String driverEarning(String id) => '/driver/earnings/$id';
  static const driverNotifications = '/driver/notifications';
  static const driverEmergencyContacts = '/driver/emergency-contacts';
  static const driverSupport = '/driver/support';
  static const driverSupportNew = '/driver/support/new';
  static const driverComplaintPattern = '/driver/support/:id';
  static String driverComplaint(String id) => '/driver/support/$id';
  // Approved drivers' own details, vehicle, documents and reviews.
  static const driverAccount = '/driver/account';
  static const driverDetails = '/driver/account/details';
  static const driverVehicleDetails = '/driver/account/vehicle';
  static const driverDocuments = '/driver/account/documents';
  static const driverReviews = '/driver/account/ratings';
  static const driverSettings = '/driver/settings';
  static const driverEditProfile = '/driver/settings/profile';
  static const driverChangePassword = '/driver/settings/password';

  // ── Screens both roles have (Phase 5), under the role's own prefix ──
  static String notificationsFor(bool isDriver) =>
      isDriver ? driverNotifications : customerNotifications;
  static String emergencyContactsFor(bool isDriver) =>
      isDriver ? driverEmergencyContacts : customerEmergencyContacts;
  static String supportFor(bool isDriver) =>
      isDriver ? driverSupport : customerSupport;
  static String settingsFor(bool isDriver) =>
      isDriver ? driverSettings : customerSettings;
  static String editProfileFor(bool isDriver) =>
      isDriver ? driverEditProfile : customerEditProfile;
  static String changePasswordFor(bool isDriver) =>
      isDriver ? driverChangePassword : customerChangePassword;
  static String complaintFor(bool isDriver, String id) =>
      isDriver ? driverComplaint(id) : customerComplaint(id);

  /// "Report an issue", optionally about one ride.
  static String newComplaintFor(bool isDriver, {String? rideId}) {
    final base = isDriver ? driverSupportNew : customerSupportNew;
    return rideId == null ? base : '$base?rideId=$rideId';
  }

  static const adminUnsupported = '/admin-unsupported';
}
