import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Mirrors the backend `ComplaintCategory`.
enum ComplaintCategory {
  driverBehaviour(
    'DRIVER_BEHAVIOUR',
    'Driver behaviour',
    Icons.person_off_outlined,
  ),
  customerBehaviour(
    'CUSTOMER_BEHAVIOUR',
    'Customer behaviour',
    Icons.person_off_outlined,
  ),
  safety('SAFETY', 'Safety concern', Icons.health_and_safety_outlined),
  fare('FARE', 'Fare', Icons.currency_rupee),
  payment('PAYMENT', 'Payment', Icons.payments_outlined),
  rideIssue('RIDE_ISSUE', 'Problem with the ride', Icons.route_outlined),
  lostItem('LOST_ITEM', 'Lost item', Icons.backpack_outlined),
  technical('TECHNICAL', 'App problem', Icons.phonelink_erase_outlined),
  other('OTHER', 'Something else', Icons.help_outline);

  const ComplaintCategory(this.wireName, this.label, this.icon);

  final String wireName;
  final String label;
  final IconData icon;

  static ComplaintCategory fromWire(String? value) => values.firstWhere(
    (category) => category.wireName == value,
    orElse: () => ComplaintCategory.other,
  );

  /// Server rule: customers report drivers, drivers report customers.
  bool availableTo({required bool isDriver}) => switch (this) {
    driverBehaviour => !isDriver,
    customerBehaviour => isDriver,
    _ => true,
  };

  /// Categories about one trip: they need a ride attached.
  bool get needsRide => switch (this) {
    driverBehaviour ||
    customerBehaviour ||
    fare ||
    rideIssue ||
    lostItem => true,
    _ => false,
  };
}

/// Mirrors the backend `ComplaintStatus`.
enum ComplaintStatus {
  open('OPEN', 'Open'),
  inReview('IN_REVIEW', 'In review'),
  resolved('RESOLVED', 'Resolved'),
  closed('CLOSED', 'Closed');

  const ComplaintStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  static ComplaintStatus fromWire(String? value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => ComplaintStatus.open,
  );

  ({Color background, Color foreground}) get colors => switch (this) {
    open => (
      background: const Color(0xFFE0F2FE),
      foreground: const Color(0xFF075985),
    ),
    inReview => (
      background: const Color(0xFFFEF3C7),
      foreground: const Color(0xFF92400E),
    ),
    resolved => (
      background: const Color(0xFFDCFCE7),
      foreground: const Color(0xFF166534),
    ),
    closed => (
      background: AppColors.surfaceSand,
      foreground: AppColors.onSurfaceVariant,
    ),
  };
}

@immutable
class Complaint {
  const Complaint({
    required this.id,
    required this.ticketCode,
    required this.category,
    required this.subject,
    required this.description,
    required this.status,
    required this.createdAt,
    this.rideId,
    this.rideCode,
    this.resolution,
    this.timeline = const [],
  });

  factory Complaint.fromJson(Map<String, dynamic> json) => Complaint(
    id: json['id'] as String,
    ticketCode: json['ticketCode'] as String,
    category: ComplaintCategory.fromWire(json['category'] as String?),
    subject: json['subject'] as String? ?? '',
    description: json['description'] as String? ?? '',
    status: ComplaintStatus.fromWire(json['status'] as String?),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    rideId: json['rideId'] as String?,
    rideCode: json['rideCode'] as String?,
    resolution: json['resolution'] as String?,
    timeline: (json['timeline'] as List<dynamic>? ?? const [])
        .map((entry) => entry as Map<String, dynamic>)
        .map(
          (entry) => (
            status: ComplaintStatus.fromWire(entry['status'] as String?),
            at:
                DateTime.tryParse(entry['at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
          ),
        )
        .toList(),
  );

  final String id;
  final String ticketCode;
  final ComplaintCategory category;
  final String subject;
  final String description;
  final ComplaintStatus status;
  final DateTime createdAt;
  final String? rideId;
  final String? rideCode;

  /// The support team's answer, once resolved.
  final String? resolution;
  final List<({ComplaintStatus status, DateTime at})> timeline;
}

@immutable
class ComplaintPage {
  const ComplaintPage({
    required this.items,
    required this.hasMore,
    required this.page,
  });

  factory ComplaintPage.fromJson(Map<String, dynamic> json) => ComplaintPage(
    items: (json['items'] as List<dynamic>)
        .map((item) => Complaint.fromJson(item as Map<String, dynamic>))
        .toList(),
    hasMore: json['hasMore'] as bool? ?? false,
    page: (json['page'] as num?)?.toInt() ?? 1,
  );

  final List<Complaint> items;
  final bool hasMore;
  final int page;
}
