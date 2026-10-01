import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../application/booking_controller.dart';
import '../../data/ride_repository.dart';
import '../../domain/promo_models.dart';
import '../../domain/ride_formatters.dart';
import '../../domain/ride_models.dart';
import '../widgets/ride_widgets.dart';

/// Live offers listed in the app (codes an admin flagged "show in app").
final promoOffersProvider = FutureProvider.autoDispose<List<PromoOffer>>(
  (ref) => ref.watch(rideRepositoryProvider).promoOffers(),
);

/// Uses [code]: on "Choose a ride" (a trip and ride type are set) the server
/// prices it for that ride; anywhere else it is checked and saved, then
/// applied automatically when the rider chooses a ride. Returns the line to
/// confirm it with; throws the server's ApiException when it cannot be used.
Future<String> usePromoCode(WidgetRef ref, String code) async {
  final controller = ref.read(bookingControllerProvider.notifier);
  final booking = ref.read(bookingControllerProvider);
  if (booking.hasTrip && booking.selectedType != null) {
    final quote = await controller.applyPromo(code);
    return '${quote.code} applied · you save ${RideFormat.money(quote.discount)}';
  }
  final offer = await controller.savePromo(code);
  return '${offer.code} saved · it will be applied when you choose a ride';
}

/// Enter or pick a promo code. The server decides whether the code applies;
/// this sheet only shows its answer. Resolves to the confirmation line, or
/// null when dismissed.
Future<String?> showPromoCodeSheet(BuildContext context, {String? code}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _PromoCodeSheet(initialCode: code),
    ),
  );
}

class _PromoCodeSheet extends ConsumerStatefulWidget {
  const _PromoCodeSheet({this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<_PromoCodeSheet> createState() => _PromoCodeSheetState();
}

class _PromoCodeSheetState extends ConsumerState<_PromoCodeSheet> {
  late final _code = TextEditingController(text: widget.initialCode);
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply([String? code]) async {
    final value = (code ?? _code.text).trim().toUpperCase();
    if (value.length < 3) {
      setState(() => _error = 'Enter a promo code');
      return;
    }
    _code.text = value;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final message = await usePromoCode(ref, value);
      if (mounted) Navigator.of(context).pop(message);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offers = ref.watch(promoOffersProvider).value ?? const [];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Apply a promo code',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    autofocus: widget.initialCode == null,
                    enabled: !_checking,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 20,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                      _UpperCaseFormatter(),
                    ],
                    onSubmitted: (_) => _apply(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: AppColors.midnightBlue,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Promo code',
                      hintText: 'e.g. BRAJ20',
                      filled: true,
                      fillColor: Colors.white,
                      border: const OutlineInputBorder(),
                      errorText: _error,
                      errorMaxLines: 3,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _checking ? null : _apply,
                  // The app theme makes filled buttons full width; in a Row
                  // that is an infinite width and breaks the whole sheet.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 56),
                    backgroundColor: AppColors.midnightBlue,
                  ),
                  child: _checking
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Apply'),
                ),
              ],
            ),
            if (offers.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Available offers',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final offer in offers)
                PromoOfferCard(
                  offer: offer,
                  onUse: _checking ? null : () => _apply(offer.code),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/// One offer: code, what it gives, and its conditions.
class PromoOfferCard extends StatelessWidget {
  const PromoOfferCard({
    super.key,
    required this.offer,
    required this.onUse,
    this.saved = false,
  });

  final PromoOffer offer;
  final VoidCallback? onUse;

  /// This is the rider's saved code.
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final conditions = [
      if (offer.minRideValue != null)
        'On fares from ${RideFormat.money(offer.minRideValue!)}',
      if (offer.rideTypes.isNotEmpty)
        'For ${offer.rideTypes.map((code) => RideTypeCode.fromWire(code).label).join(', ')}',
      'Valid till ${_day(offer.endsAt)}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: saved
              ? const Color(0xFF15803D)
              : AppColors.bhagwa.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.local_offer_rounded, color: AppColors.bhagwa),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bhagwaLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          offer.code,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: AppColors.bhagwaDark,
                          ),
                        ),
                      ),
                      Text(
                        offer.summary,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  if (offer.title.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(offer.title),
                  ],
                  if (offer.description?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 2),
                    Text(
                      offer.description!,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    conditions.join(' · '),
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            if (saved)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Saved',
                  style: TextStyle(
                    color: Color(0xFF15803D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              TextButton(onPressed: onUse, child: const Text('Use')),
          ],
        ),
      ),
    );
  }

  static String _day(DateTime value) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }
}
