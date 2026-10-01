import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../rides/domain/ride_models.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';
import '../application/saved_places.dart';
import '../domain/saved_place.dart';

IconData savedPlaceIcon(SavedPlaceKind kind) => switch (kind) {
  SavedPlaceKind.home => Icons.home_rounded,
  SavedPlaceKind.work => Icons.work_rounded,
};

/// Home / Work shortcut on the "Where to?" screen: the saved address, or
/// "Add address" when there is none yet.
class SavedPlaceCard extends StatelessWidget {
  const SavedPlaceCard({
    super.key,
    required this.kind,
    required this.saved,
    required this.onTap,
    this.loading = false,
    this.onLongPress,
  });

  final SavedPlaceKind kind;
  final Place? saved;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final subtitle = saved?.title ?? (loading ? '…' : 'Add address');
    return Semantics(
      button: true,
      label: saved == null
          ? 'Add ${kind.label.toLowerCase()} address'
          : '${kind.label}: ${saved!.title}',
      excludeSemantics: true,
      child: Material(
        color: const Color(0xFFF8FAFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    savedPlaceIcon(kind),
                    color: const Color(0xFF0F172A),
                    size: 17,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        kind.label,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                          height: 1.2,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          // "Add address" reads as an action, like on Home.
                          fontWeight: saved == null
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: saved == null && !loading
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Long-press on a saved Home/Work: change it or remove it. Completes once
/// the rider is back (after the change screen closes, if they chose it).
Future<void> showSavedPlaceOptions(
  BuildContext context,
  WidgetRef ref,
  SavedPlaceKind kind,
) async {
  final saved = ref.read(savedPlacesProvider).value?[kind];
  final action = await showModalBottomSheet<_SavedPlaceAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kind.label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (saved != null)
                  Text(
                    saved.address,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_location_alt_outlined),
            title: Text('Change ${kind.label.toLowerCase()} address'),
            onTap: () =>
                Navigator.of(sheetContext).pop(_SavedPlaceAction.change),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
            title: Text(
              'Remove ${kind.label.toLowerCase()}',
              style: const TextStyle(color: Color(0xFFDC2626)),
            ),
            onTap: () =>
                Navigator.of(sheetContext).pop(_SavedPlaceAction.remove),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case _SavedPlaceAction.change:
      await context.push(AppRoutes.customerSavePlace(kind.name));
    case _SavedPlaceAction.remove:
      try {
        await ref.read(savedPlacesProvider.notifier).clear(kind);
      } on Object catch (error) {
        if (context.mounted) showErrorSnack(context, error);
      }
  }
}

enum _SavedPlaceAction { change, remove }
