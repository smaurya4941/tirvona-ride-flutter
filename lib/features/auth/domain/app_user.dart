enum UserRole { customer, driver, admin }

enum UserStatus { active, inactive, blocked }

/// Values the API accepts for `gender` (PATCH /users/me).
enum Gender {
  male('Male'),
  female('Female'),
  other('Other');

  const Gender(this.label);

  final String label;

  static Gender? tryParse(String? value) {
    for (final gender in Gender.values) {
      if (gender.name == value) return gender;
    }
    return null;
  }
}

/// Mirrors the backend's `DriverStatus` enum (driver_profiles.driverStatus).
enum DriverStatus { pending, underReview, approved, rejected, suspended }

UserRole userRoleFromJson(String value) => UserRole.values.firstWhere(
  (role) => role.name.toUpperCase() == value,
  orElse: () => UserRole.customer,
);

String userRoleToJson(UserRole role) => role.name.toUpperCase();

/// A date of birth is a calendar day: the API stores it as UTC midnight, so
/// read the UTC parts (converting to local time could move it a day).
DateTime? _calendarDate(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) return null;
  final utc = parsed.toUtc();
  return DateTime(utc.year, utc.month, utc.day);
}

UserStatus _userStatusFromJson(String value) => UserStatus.values.firstWhere(
  (status) => status.name.toUpperCase() == value,
  orElse: () => UserStatus.active,
);

DriverStatus driverStatusFromJson(String value) =>
    DriverStatus.values.firstWhere(
      (status) => _driverStatusWireName(status) == value,
      orElse: () => DriverStatus.pending,
    );

String _driverStatusWireName(DriverStatus status) => switch (status) {
  DriverStatus.pending => 'PENDING',
  DriverStatus.underReview => 'UNDER_REVIEW',
  DriverStatus.approved => 'APPROVED',
  DriverStatus.rejected => 'REJECTED',
  DriverStatus.suspended => 'SUSPENDED',
};

class DriverStatusInfo {
  const DriverStatusInfo({required this.driverStatus, this.rejectionReason});

  factory DriverStatusInfo.fromJson(Map<String, dynamic> json) =>
      DriverStatusInfo(
        driverStatus: driverStatusFromJson(json['driverStatus'] as String),
        rejectionReason: json['rejectionReason'] as String?,
      );

  final DriverStatus driverStatus;
  final String? rejectionReason;
}

/// The authenticated user, as returned by `/auth/login`, `/auth/register`
/// and `/auth/me`. `driver` is present only when `role == UserRole.driver`.
class AppUser {
  const AppUser({
    required this.id,
    required this.phone,
    required this.role,
    required this.status,
    required this.firstName,
    this.email,
    this.lastName,
    this.profileImage,
    this.gender,
    this.dateOfBirth,
    this.isPhoneVerified = false,
    this.isEmailVerified = false,
    this.driver,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    phone: json['phone'] as String,
    email: json['email'] as String?,
    role: userRoleFromJson(json['role'] as String),
    status: _userStatusFromJson(json['status'] as String),
    firstName: json['firstName'] as String,
    lastName: json['lastName'] as String?,
    profileImage: json['profileImage'] as String?,
    gender: Gender.tryParse(json['gender'] as String?),
    dateOfBirth: _calendarDate(json['dob'] as String?),
    isPhoneVerified: json['isPhoneVerified'] as bool? ?? false,
    isEmailVerified: json['isEmailVerified'] as bool? ?? false,
    driver: json['driver'] == null
        ? null
        : DriverStatusInfo.fromJson(json['driver'] as Map<String, dynamic>),
  );

  final String id;
  final String phone;
  final String? email;
  final UserRole role;
  final UserStatus status;
  final String firstName;
  final String? lastName;

  /// App path of the profile photo ('/users/me/profile-image?v=…'), fetched
  /// with the session's token; a new photo gets a new path.
  final String? profileImage;
  final Gender? gender;
  final DateTime? dateOfBirth;
  final bool isPhoneVerified;
  final bool isEmailVerified;
  final DriverStatusInfo? driver;

  /// The same user with the driver status of [previous]: `PATCH /users/me`
  /// and the photo endpoints return the account without it.
  AppUser withDriverFrom(AppUser? previous) => AppUser(
    id: id,
    phone: phone,
    email: email,
    role: role,
    status: status,
    firstName: firstName,
    lastName: lastName,
    profileImage: profileImage,
    gender: gender,
    dateOfBirth: dateOfBirth,
    isPhoneVerified: isPhoneVerified,
    isEmailVerified: isEmailVerified,
    driver: driver ?? previous?.driver,
  );

  String get initials => [firstName, lastName ?? '']
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase())
      .join();

  String get displayName => [
    firstName,
    lastName,
  ].where((part) => part != null && part.isNotEmpty).join(' ');
}
