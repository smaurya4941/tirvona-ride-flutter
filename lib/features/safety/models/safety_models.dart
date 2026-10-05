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

/// Whether one emergency contact received the WhatsApp alert (no phone number).
enum SosContactState {
  sent,
  failed,
  pending;

  static SosContactState fromWire(String? value) => switch (value) {
    'SENT' => SosContactState.sent,
    'FAILED' => SosContactState.failed,
    _ => SosContactState.pending,
  };
}

@immutable
class SosContactStatus {
  const SosContactStatus({required this.name, required this.state});

  factory SosContactStatus.fromJson(Map<String, dynamic> json) =>
      SosContactStatus(
        name: json['name'] as String? ?? '',
        state: SosContactState.fromWire(json['status'] as String?),
      );

  final String name;
  final SosContactState state;
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
    this.contacts = const [],
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
    contacts: [
      for (final item in json['contacts'] as List<dynamic>? ?? const [])
        SosContactStatus.fromJson(item as Map<String, dynamic>),
    ],
  );

  final String id;
  final String sosCode;
  final String rideId;
  final SosStatus status;
  final DateTime triggeredAt;

  /// DEVICE | DRIVER_LAST_KNOWN | RIDE_PICKUP.
  final String locationSource;

  /// The emergency contacts messaged on WhatsApp with the live location.
  final List<SosContactStatus> contacts;

  bool get contactsStillSending =>
      contacts.any((contact) => contact.state == SosContactState.pending);
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
