import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';
import '../repository/safety_repository.dart';

/// "Share ride" for the customer's active ride. The server creates the
/// secure link (the app never builds a token); the phone's share sheet
/// sends it by WhatsApp, SMS, etc. "Stop sharing" kills every link.
class ShareRideButton extends ConsumerStatefulWidget {
  const ShareRideButton({super.key, required this.rideId});

  final String rideId;

  @override
  ConsumerState<ShareRideButton> createState() => _ShareRideButtonState();
}

class _ShareRideButtonState extends ConsumerState<ShareRideButton> {
  bool _working = false;

  Future<void> _share() async {
    setState(() => _working = true);
    try {
      final link = await ref
          .read(safetyRepositoryProvider)
          .createShareLink(widget.rideId);
      ref.invalidate(activeShareLinksProvider(widget.rideId));
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: link.shareText,
          subject: 'Follow my Tirvona ride',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _working = true);
    try {
      await ref.read(safetyRepositoryProvider).stopSharing(widget.rideId);
      ref.invalidate(activeShareLinksProvider(widget.rideId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your ride is no longer shared.')),
      );
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active =
        ref.watch(activeShareLinksProvider(widget.rideId)).value ?? 0;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppColors.midnightBlue,
            ),
            onPressed: _working ? null : _share,
            icon: _working
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_location),
            label: Text(active > 0 ? 'Share again' : 'Share ride'),
          ),
        ),
        if (active > 0) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: _working ? null : _stop,
            child: const Text('Stop sharing'),
          ),
        ],
      ],
    );
  }
}
