/// `GET /rides/:id/cancellation` — everything the cancel sheet needs before
/// the rider or driver confirms. The server owns the reason list and the fee.
class CancellationReasonOption {
  const CancellationReasonOption({
    required this.code,
    required this.label,
    required this.requiresNote,
  });

  factory CancellationReasonOption.fromJson(Map<String, dynamic> json) =>
      CancellationReasonOption(
        code: json['code'] as String,
        label: json['label'] as String? ?? json['code'] as String,
        requiresNote: json['requiresNote'] as bool? ?? false,
      );

  final String code;
  final String label;

  /// "Other"-style reasons need a short note.
  final bool requiresNote;
}

class CancellationFee {
  const CancellationFee({
    required this.amount,
    required this.applies,
    required this.explanation,
    this.freeUntil,
  });

  factory CancellationFee.fromJson(Map<String, dynamic> json) =>
      CancellationFee(
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        applies: json['applies'] as bool? ?? false,
        explanation: json['explanation'] as String? ?? '',
        freeUntil: json['freeUntil'] is String
            ? DateTime.tryParse(json['freeUntil'] as String)?.toLocal()
            : null,
      );

  final double amount;
  final bool applies;

  /// One line from the server, shown verbatim.
  final String explanation;

  /// When a currently free cancellation starts costing money.
  final DateTime? freeUntil;
}

class CancellationPreview {
  const CancellationPreview({
    required this.cancellable,
    required this.reasons,
    required this.fee,
  });

  factory CancellationPreview.fromJson(Map<String, dynamic> json) =>
      CancellationPreview(
        cancellable: json['cancellable'] as bool? ?? false,
        reasons: (json['reasons'] as List<dynamic>? ?? const [])
            .map(
              (item) => CancellationReasonOption.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
        fee: CancellationFee.fromJson(
          json['fee'] as Map<String, dynamic>? ?? const {},
        ),
      );

  final bool cancellable;
  final List<CancellationReasonOption> reasons;
  final CancellationFee fee;
}
