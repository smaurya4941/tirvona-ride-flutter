import 'package:flutter/foundation.dart';

@immutable
class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.isPrimary,
    this.relationship,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
        relationship: json['relationship'] as String?,
        isPrimary: json['isPrimary'] as bool? ?? false,
      );

  final String id;
  final String name;

  /// E.164 (the server normalises what was typed).
  final String phone;
  final String? relationship;
  final bool isPrimary;
}

/// Mirrors the backend `SosStatus`.
enum SosStatus {
  triggered('TRIGGERED'),
  acknowledged('ACKNOWLEDGED'),
  inProgress('IN_PROGRESS'),
  resolved('RESOLVED'),
  cancelled('CANCELLED');

  const SosStatus(this.wireName);

  final String wireName;

  static SosStatus fromWire(String? value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => SosStatus.triggered,
  );

  bool get isOpen =>
      this == triggered || this == acknowledged || this == inProgress;

  String get label => switch (this) {
    triggered => 'Alert sent — waiting for the safety team',
    acknowledged => 'Safety team has seen your alert',
    inProgress => 'Safety team is handling your alert',
    resolved => 'Resolved',
    cancelled => 'Closed',
  };
}

@immutable
class SosAlert {
  const SosAlert({
    required this.id,
    required this.sosCode,
    required this.rideId,
    required this.status,
    required this.triggeredAt,
    required this.locationSource,
  });

  factory SosAlert.fromJson(Map<String, dynamic> json) => SosAlert(
    id: json['id'] as String,
    sosCode: json['sosCode'] as String,
    rideId: json['rideId'] as String,
    status: SosStatus.fromWire(json['status'] as String?),
    triggeredAt:
        DateTime.tryParse(json['triggeredAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    locationSource:
        (json['location'] as Map<String, dynamic>?)?['source'] as String? ??
        'DEVICE',
  );

  final String id;
  final String sosCode;
  final String rideId;
  final SosStatus status;
  final DateTime triggeredAt;

  /// DEVICE | DRIVER_LAST_KNOWN | RIDE_PICKUP.
  final String locationSource;
}

@immutable
class ShareLink {
  const ShareLink({
    required this.url,
    required this.shareText,
    required this.expiresAt,
  });

  factory ShareLink.fromJson(Map<String, dynamic> json) => ShareLink(
    url: json['url'] as String,
    shareText: json['shareText'] as String? ?? json['url'] as String,
    expiresAt:
        DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );

  final String url;
  final String shareText;
  final DateTime expiresAt;
}

/// A GPS fix to attach to an SOS (all optional: the server falls back).
@immutable
class SosFix {
  const SosFix({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
}
