import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/earning_models.dart';
import '../repository/earnings_repository.dart';

/// The period chip selected on the Earnings tab.
class EarningsPeriodController extends Notifier<EarningsPeriod> {
  @override
  EarningsPeriod build() => EarningsPeriod.today;

  void select(EarningsPeriod period) => state = period;
}

final earningsPeriodProvider =
    NotifierProvider<EarningsPeriodController, EarningsPeriod>(
      EarningsPeriodController.new,
    );

/// First page of the ledger for a period, with the summary.
final earningsFirstPageProvider = FutureProvider.autoDispose
    .family<EarningsPage, EarningsPeriod>(
      (ref, period) =>
          ref.watch(earningsRepositoryProvider).list(period: period),
    );

final earningDetailProvider = FutureProvider.autoDispose
    .family<Earning, String>(
      (ref, id) => ref.watch(earningsRepositoryProvider).detail(id),
    );
