import 'package:flutter/foundation.dart';

/// What an approved driver asked to change (`DriverChangeKind` on the API).
enum DriverChangeKind {
  driverProfile('DRIVER_PROFILE'),
  vehicle('VEHICLE'),
  driverDocument('DRIVER_DOCUMENT'),
  vehicleDocument('VEHICLE_DOCUMENT');

  const DriverChangeKind(this.wireName);

  final String wireName;

  static DriverChangeKind fromWire(String value) => values.firstWhere(
    (kind) => kind.wireName == value,
    orElse: () => DriverChangeKind.driverDocument,
  );
}

enum DriverChangeStatus {
  pending,
  approved,
  rejected,
  withdrawn;

  static DriverChangeStatus fromWire(String value) => values.firstWhere(
    (status) => status.name.toUpperCase() == value,
    orElse: () => DriverChangeStatus.pending,
  );

  String get label => switch (this) {
    DriverChangeStatus.pending => 'Under review',
    DriverChangeStatus.approved => 'Approved',
    DriverChangeStatus.rejected => 'Not approved',
    DriverChangeStatus.withdrawn => 'Withdrawn',
  };
}

/// A change to verified details that an admin reviews before it applies.
/// The verified details stay live — the driver keeps driving — meanwhile.
@immutable
class DriverChangeRequest {
  const DriverChangeRequest({
    required this.id,
    required this.kind,
    required this.label,
    required this.status,
    required this.changes,
    required this.previous,
    required this.hasFile,
    required this.submittedAt,
    this.vehicleId,
    this.documentType,
    this.reviewNote,
    this.reviewedAt,
  });

  factory DriverChangeRequest.fromJson(Map<String, dynamic> json) =>
      DriverChangeRequest(
        id: json['id'] as String,
        kind: DriverChangeKind.fromWire(json['kind'] as String),
        label: json['label'] as String? ?? 'Update',
        status: DriverChangeStatus.fromWire(json['status'] as String),
        changes: Map<String, dynamic>.from(json['changes'] as Map? ?? {}),
        previous: Map<String, dynamic>.from(json['previous'] as Map? ?? {}),
        hasFile: json['hasFile'] as bool? ?? false,
        submittedAt:
            DateTime.tryParse(json['submittedAt'] as String? ?? '') ??
            DateTime.now(),
        vehicleId: json['vehicleId'] as String?,
        documentType: json['documentType'] as String?,
        reviewNote: json['reviewNote'] as String?,
        reviewedAt: DateTime.tryParse(json['reviewedAt'] as String? ?? ''),
      );

  final String id;
  final DriverChangeKind kind;

  /// "Driving licence", "Vehicle details", … from the server.
  final String label;
  final DriverChangeStatus status;

  /// Requested values by field (dates as ISO strings).
  final Map<String, dynamic> changes;

  /// The verified values they would replace.
  final Map<String, dynamic> previous;
  final bool hasFile;
  final DateTime submittedAt;
  final String? vehicleId;
  final String? documentType;
  final String? reviewNote;
  final DateTime? reviewedAt;

  bool get isPending => status == DriverChangeStatus.pending;
}

/// `GET /drivers/me/change-requests`.
@immutable
class DriverChangesOverview {
  const DriverChangesOverview({
    this.pending = const [],
    this.history = const [],
  });

  factory DriverChangesOverview.fromJson(Map<String, dynamic> json) {
    List<DriverChangeRequest> list(Object? raw) => [
      for (final item in raw as List<dynamic>? ?? const [])
        DriverChangeRequest.fromJson(item as Map<String, dynamic>),
    ];
    return DriverChangesOverview(
      pending: list(json['pending']),
      history: list(json['history']),
    );
  }

  final List<DriverChangeRequest> pending;

  /// Decided or withdrawn, newest first.
  final List<DriverChangeRequest> history;

  DriverChangeRequest? pendingFor(
    DriverChangeKind kind, {
    String? documentType,
    String? vehicleId,
  }) {
    for (final request in pending) {
      if (request.kind != kind) continue;
      if (documentType != null && request.documentType != documentType) {
        continue;
      }
      if (vehicleId != null && request.vehicleId != vehicleId) continue;
      return request;
    }
    return null;
  }

  /// The latest rejection for a target, if nothing newer is pending.
  DriverChangeRequest? lastRejectedFor(
    DriverChangeKind kind, {
    String? documentType,
    String? vehicleId,
  }) {
    if (pendingFor(kind, documentType: documentType, vehicleId: vehicleId) !=
        null) {
      return null;
    }
    for (final request in history) {
      if (request.kind != kind) continue;
      if (documentType != null && request.documentType != documentType) {
        continue;
      }
      if (vehicleId != null && request.vehicleId != vehicleId) continue;
      return request.status == DriverChangeStatus.rejected ? request : null;
    }
    return null;
  }
}

/// One rating as the driver sees it: stars, comment and day — never who.
@immutable
class DriverReview {
  const DriverReview({
    required this.key,
    required this.rating,
    required this.ratedOn,
    this.comment,
  });

  factory DriverReview.fromJson(Map<String, dynamic> json) {
    final day = DateTime.tryParse(json['ratedOn'] as String? ?? '');
    return DriverReview(
      key: json['key'] as String,
      rating: (json['rating'] as num).toInt(),
      comment: json['comment'] as String?,
      ratedOn: day == null
          ? DateTime.now()
          : DateTime(day.year, day.month, day.day),
    );
  }

  final String key;
  final int rating;
  final String? comment;

  /// A calendar day (no time: reviews stay anonymous).
  final DateTime ratedOn;
}

@immutable
class DriverReviewsPage {
  const DriverReviewsPage({required this.items, this.nextCursor});

  factory DriverReviewsPage.fromJson(Map<String, dynamic> json) =>
      DriverReviewsPage(
        items: [
          for (final item in json['items'] as List<dynamic>? ?? const [])
            DriverReview.fromJson(item as Map<String, dynamic>),
        ],
        nextCursor: json['nextCursor'] as String?,
      );

  final List<DriverReview> items;
  final String? nextCursor;
}
