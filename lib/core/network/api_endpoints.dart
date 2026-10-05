/// Paths relative to `AppConfig.apiBaseUrl` (`.../api/v1`).
abstract final class ApiEndpoints {
  static const health = '/health';
  static const healthLive = '/health/live';

  static const authRegister = '/auth/register';
  static const authLogin = '/auth/login';
  // Login with a WhatsApp code instead of the password.
  static const authLoginOtpRequest = '/auth/login/otp/request';
  static const authLoginOtpVerify = '/auth/login/otp/verify';
  static const authRefresh = '/auth/refresh';
  static const authLogout = '/auth/logout';
  // Signup: register sends a WhatsApp code; verify-otp creates the account.
  static const authVerifyOtp = '/auth/verify-otp';
  static const authResendOtp = '/auth/resend-otp';
  // Signed-in accounts created before signup OTP verify their own number.
  static const authPhoneSendOtp = '/auth/phone/send-otp';
  static const authPhoneVerifyOtp = '/auth/phone/verify-otp';
  static const authMe = '/auth/me';
  static const authLogoutAll = '/auth/logout-all';
  // Forgot password: WhatsApp code → one-time reset token → new password.
  static const authPasswordForgot = '/auth/password/forgot';
  static const authPasswordVerifyOtp = '/auth/password/verify-otp';
  static const authPasswordReset = '/auth/password/reset';

  static const usersMe = '/users/me';
  static const usersMePassword = '/users/me/password';
  static const usersProfileImage = '/users/profile-image';

  static const driversMe = '/drivers/me';
  static const driversMeDocuments = '/drivers/me/documents';
  static String driversMeDocument(String id) => '/drivers/me/documents/$id';
  static String driversMeDocumentFile(String id) =>
      '/drivers/me/documents/$id/file';
  static const driversMeSubmitKyc = '/drivers/me/submit-kyc';
  // After approval: changes to verified details go through admin review.
  static const driverChangeRequests = '/drivers/me/change-requests';
  static const driverChangeProfile = '/drivers/me/change-requests/profile';
  static const driverChangeVehicle = '/drivers/me/change-requests/vehicle';
  static const driverChangeDocument = '/drivers/me/change-requests/document';
  static String driverChangeRequest(String id) =>
      '/drivers/me/change-requests/$id';
  static const driverReviews = '/drivers/me/ratings/reviews';

  static const vehicles = '/vehicles';
  static const vehiclesMy = '/vehicles/my';
  static String vehicle(String id) => '/vehicles/$id';
  static String vehicleDocuments(String id) => '/vehicles/$id/documents';

  static const rideTypes = '/ride-types';

  static const rides = '/rides';
  static const ridesEstimate = '/rides/estimate';
  static const ridesEstimateAll = '/rides/estimate/all';
  static const ridesActive = '/rides/active';
  static const ridesRequests = '/rides/requests';
  static String ride(String id) => '/rides/$id';
  static String rideAction(String id, String action) => '/rides/$id/$action';
  static String rideCancellation(String id) => '/rides/$id/cancellation';
  static String rideRoute(String id) => '/rides/$id/route';

  // Tirvona Circuit
  static const circuitPackages = '/circuit-packages';
  static String circuitPackage(String id) => '/circuit-packages/$id';
  static const circuitRides = '/circuit-rides';
  static const circuitEstimate = '/circuit-rides/estimate';
  static String circuitAction(String id, String action) =>
      '/circuit-rides/$id/$action';
  static String circuitStopAction(String id, int order, String action) =>
      '/circuit-rides/$id/stops/$order/$action';

  // ── Phase 7 ───────────────────────────────────────────────────────────
  static const promotions = '/promotions';
  static const promotionsValidate = '/promotions/validate';
  static const promotionsCheck = '/promotions/check';

  // Place search for pickup/destination (proxied, cached geocoding).
  static const branding = '/branding';

  static const placesAutocomplete = '/places/autocomplete';
  static const placesResolve = '/places/resolve';
  static const placesReverse = '/places/reverse';
  static const placesPopular = '/places/popular';
  // The rider's Home / Work shortcuts (server-side, follow the account).
  static const placesSaved = '/places/saved';
  static String placesSavedKind(String kind) => '/places/saved/$kind';
  static const placesSavedOthers = '/places/saved/others';
  static String placesSavedOther(String id) => '/places/saved/others/$id';
  // Rider Home: free cars around the pickup, and past destinations.
  static const ridesNearbyDrivers = '/rides/nearby-drivers';
  static const ridesRecentDestinations = '/rides/recent-destinations';

  static const driversAvailability = '/drivers/availability';
  static const driversLocation = '/drivers/location';
  static const driversDashboard = '/drivers/dashboard';

  static const paymentsCreate = '/payments/create';
  static const paymentsVerify = '/payments/verify';
  static const paymentsCash = '/payments/cash';
  static const paymentsHistory = '/payments/history';
  static String payment(String id) => '/payments/$id';
  static String paymentFailure(String id) => '/payments/$id/failure';

  static const earnings = '/earnings';
  static String earning(String id) => '/earnings/$id';

  // ── Phase 5 ───────────────────────────────────────────────────────────
  static const notifications = '/notifications';
  static const notificationsUnreadCount = '/notifications/unread-count';
  static const notificationsReadAll = '/notifications/read-all';
  static String notificationRead(String id) => '/notifications/$id/read';
  static const notificationsDeviceToken = '/notifications/device-token';
  static const notificationsDeviceTokenDeactivate =
      '/notifications/device-token/deactivate';

  static String rideRating(String rideId) => '/rides/$rideId/rating';
  static const driverRatings = '/drivers/me/ratings';

  static const emergencyContacts = '/users/me/emergency-contacts';
  static String emergencyContact(String id) =>
      '/users/me/emergency-contacts/$id';
  static String rideSos(String rideId) => '/rides/$rideId/sos';
  static String rideShare(String rideId) => '/rides/$rideId/share';

  static const complaints = '/complaints';
  static String complaint(String id) => '/complaints/$id';
}
