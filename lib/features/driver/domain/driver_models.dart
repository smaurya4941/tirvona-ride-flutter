import '../../auth/domain/app_user.dart';

enum KycDocumentType {
  drivingLicense('DRIVING_LICENSE', 'Driving licence', required: true),
  aadhaar('AADHAAR', 'Aadhaar card', required: true),
  profilePhoto('PROFILE_PHOTO', 'Profile photo', required: true),
  pan('PAN', 'PAN card'),
  addressProof('ADDRESS_PROOF', 'Address proof');

  const KycDocumentType(this.wireName, this.label, {this.required = false});

  final String wireName;
  final String label;

  /// Mirrors `REQUIRED_DOCUMENT_TYPES` in the backend's DriversService —
  /// submit-kyc is rejected until all of these are uploaded.
  final bool required;

  static KycDocumentType fromWire(String value) =>
      values.firstWhere((type) => type.wireName == value);
}

enum DocumentStatus {
  pending,
  verified,
  rejected;

  static DocumentStatus fromWire(String value) => values.firstWhere(
    (status) => status.name.toUpperCase() == value,
    orElse: () => DocumentStatus.pending,
  );
}

enum VehicleType {
  bike('BIKE', 'Bike'),
  auto('AUTO', 'Auto'),
  eRickshaw('E_RICKSHAW', 'E-Rickshaw'),
  cab('CAB', 'Cab');

  const VehicleType(this.wireName, this.label);

  final String wireName;
  final String label;

  static VehicleType fromWire(String value) => values.firstWhere(
    (type) => type.wireName == value,
    // A vehicle type added on the server after this build: show it as a cab
    // rather than crash the driver's vehicle screen.
    orElse: () => VehicleType.cab,
  );
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

class DriverProfile {
  const DriverProfile({
    required this.id,
    required this.driverCode,
    required this.driverStatus,
    this.licenseNumber,
    this.licenseExpiry,
    this.dateOfBirth,
    this.address,
    this.rejectionReason,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
    id: json['id'] as String,
    driverCode: json['driverCode'] as String,
    driverStatus: driverStatusFromJson(json['driverStatus'] as String),
    licenseNumber: json['licenseNumber'] as String?,
    licenseExpiry: _date(json['licenseExpiry']),
    dateOfBirth: _date(json['dateOfBirth']),
    address: json['address'] as String?,
    rejectionReason: json['rejectionReason'] as String?,
  );

  final String id;
  final String driverCode;
  final DriverStatus driverStatus;
  final String? licenseNumber;
  final DateTime? licenseExpiry;
  final DateTime? dateOfBirth;
  final String? address;
  final String? rejectionReason;

  bool get hasLicenseDetails => licenseNumber != null && licenseExpiry != null;
}

class KycDocument {
  const KycDocument({
    required this.id,
    required this.documentType,
    required this.status,
    this.documentNumber,
    this.rejectionReason,
    this.expiryDate,
  });

  factory KycDocument.fromJson(Map<String, dynamic> json) => KycDocument(
    id: json['id'] as String,
    documentType: KycDocumentType.fromWire(json['documentType'] as String),
    status: DocumentStatus.fromWire(json['status'] as String),
    documentNumber: json['documentNumber'] as String?,
    rejectionReason: json['rejectionReason'] as String?,
    expiryDate: _date(json['expiryDate']),
  );

  final String id;
  final KycDocumentType documentType;
  final DocumentStatus status;
  final String? documentNumber;
  final String? rejectionReason;
  final DateTime? expiryDate;
}

/// Mirrors the backend's `VehicleDocumentType` (vehicle_documents).
enum VehicleDocumentType {
  rc('RC', 'Registration certificate (RC)'),
  insurance('INSURANCE', 'Vehicle insurance'),
  permit('PERMIT', 'Permit'),
  pollutionCertificate('POLLUTION_CERTIFICATE', 'Pollution certificate (PUC)');

  const VehicleDocumentType(this.wireName, this.label);

  final String wireName;
  final String label;

  static VehicleDocumentType? tryParse(String? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

class VehicleDocumentRecord {
  const VehicleDocumentRecord({
    required this.id,
    required this.documentType,
    required this.status,
    this.documentNumber,
    this.expiryDate,
  });

  /// Null for a document type this build does not know yet.
  static VehicleDocumentRecord? tryFromJson(Map<String, dynamic> json) {
    final type = VehicleDocumentType.tryParse(json['documentType'] as String?);
    if (type == null) return null;
    return VehicleDocumentRecord(
      id: json['id'] as String,
      documentType: type,
      status: DocumentStatus.fromWire(json['status'] as String),
      documentNumber: json['documentNumber'] as String?,
      expiryDate: _date(json['expiryDate']),
    );
  }

  final String id;
  final VehicleDocumentType documentType;
  final DocumentStatus status;
  final String? documentNumber;
  final DateTime? expiryDate;
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.vehicleType,
    required this.registrationNumber,
    required this.isActive,
    this.make,
    this.model,
    this.color,
    this.manufactureYear,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
    id: json['id'] as String,
    vehicleType: VehicleType.fromWire(json['vehicleType'] as String),
    registrationNumber: json['registrationNumber'] as String,
    isActive: json['isActive'] as bool,
    make: json['make'] as String?,
    model: json['model'] as String?,
    color: json['color'] as String?,
    manufactureYear: json['manufactureYear'] as int?,
  );

  final String id;
  final VehicleType vehicleType;
  final String registrationNumber;
  final bool isActive;
  final String? make;
  final String? model;
  final String? color;
  final int? manufactureYear;

  String get title =>
      [make, model].whereType<String>().where((s) => s.isNotEmpty).join(' ');
}
