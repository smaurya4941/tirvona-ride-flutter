import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../rides/domain/ride_formatters.dart';
import '../models/earning_models.dart';

({Color background, Color foreground}) earningStatusColors(
  EarningStatus status,
) => switch (status) {
  EarningStatus.pending => (
    background: const Color(0xFFFEF3C7),
    foreground: const Color(0xFF92400E),
  ),
  EarningStatus.available => (
    background: const Color(0xFFE0F2FE),
    foreground: const Color(0xFF075985),
  ),
  EarningStatus.paid => (
    background: const Color(0xFFDCFCE7),
    foreground: const Color(0xFF166534),
  ),
  EarningStatus.collected => (
    background: AppColors.bhagwaLight,
    foreground: AppColors.bhagwaDark,
  ),
};

/// How the customer paid this ride: "Cash" or the online method ("UPI").
class PaymentModeChip extends StatelessWidget {
  const PaymentModeChip({super.key, required this.earning});

  final Earning earning;

  @override
  Widget build(BuildContext context) {
    final cash = earning.paymentMode == PaymentMode.cash;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            cash ? Icons.payments_outlined : Icons.phone_iphone,
            size: 13,
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            cash ? 'Cash' : RideFormat.paymentMethod(earning.paymentMethod),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class EarningStatusChip extends StatelessWidget {
  const EarningStatusChip({super.key, required this.status});

  final EarningStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = earningStatusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: colors.foreground,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// One refund deduction: "Fare adjustment · Ride TR… · −₹59.50".
class AdjustmentTile extends StatelessWidget {
  const AdjustmentTile({super.key, required this.adjustment, this.onTap});

  final EarningAdjustment adjustment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final outstanding = adjustment.status == AdjustmentStatus.outstanding;
    final waived = adjustment.status == AdjustmentStatus.waived;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: waived ? AppColors.outlineVariant : const Color(0xFFFEF3C7),
        child: Icon(
          waived ? Icons.do_not_disturb_on_outlined : Icons.undo_rounded,
          size: 18,
          color: waived ? AppColors.onSurfaceVariant : const Color(0xFF92400E),
        ),
      ),
      title: Text(
        '${adjustment.reasonLabel} · Ride ${adjustment.rideCode}',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        'Customer refunded ${RideFormat.money(adjustment.refundAmount)} · '
        '${adjustment.status.label}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        waived ? RideFormat.money(0) : '−${RideFormat.money(adjustment.amount)}',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: outstanding
              ? const Color(0xFF92400E)
              : AppColors.onSurfaceVariant,
          decoration: waived ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

/// Big number with a caption ("₹2,450 · Today's earnings").
class EarningsFigure extends StatelessWidget {
  const EarningsFigure({
    super.key,
    required this.amount,
    required this.label,
    this.large = false,
    this.inverse = false,
  });

  final double amount;
  final String label;
  final bool large;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final color = inverse ? Colors.white : AppColors.midnightBlue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          RideFormat.money(amount),
          style: TextStyle(
            fontSize: large ? 34 : 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: inverse
                ? Colors.white.withValues(alpha: 0.8)
                : AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class EarningTile extends StatelessWidget {
  const EarningTile({super.key, required this.earning, required this.onTap});

  final Earning earning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ride ${earning.rideCode}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${RideFormat.dateTime(earning.rideCompletedAt)} · '
                      'fare ${RideFormat.money(earning.grossFare)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        EarningStatusChip(status: earning.status),
                        PaymentModeChip(earning: earning),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    RideFormat.money(earning.netEarning),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: AppColors.success,
                    ),
                  ),
                  Text(
                    '−${RideFormat.money(earning.commissionAmount)} commission',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
