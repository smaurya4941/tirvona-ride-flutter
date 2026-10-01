import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../rides/domain/ride_models.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';
import '../application/saved_places.dart';
import '../domain/saved_place.dart';
import 'saved_place_actions.dart';

/// Quick labels offered when naming a new place.
const _labelSuggestions = [
  'Gym',
  'School',
  'College',
  'Temple',
  'Hospital',
  'Friend\'s place',
];

const _maxLabelLength = 40;

/// Every address the rider has saved: Home, Work and their own labelled
/// places. All of them show up on "Where to?" for one-tap booking.
class SavedPlacesScreen extends ConsumerStatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  ConsumerState<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends ConsumerState<SavedPlacesScreen> {
  bool _busy = false;

  SavedPlacesController get _controller =>
      ref.read(savedPlacesProvider.notifier);

  Future<void> _run(Future<void> Function() task, String done) async {
    setState(() => _busy = true);
    try {
      await task();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
      }
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Place?> _pickAddress() =>
      context.push<Place>(AppRoutes.customerPickAddress);

  Future<void> _add() async {
    final place = await _pickAddress();
    if (place == null || !mounted) return;
    final label = await _askLabel(title: 'Name this place', place: place);
    if (label == null || !mounted) return;
    await _run(() => _controller.addOther(label, place), '"$label" saved');
  }

  Future<void> _rename(OtherSavedPlace other) async {
    final label = await _askLabel(
      title: 'Rename place',
      initial: other.label,
      editingId: other.id,
      place: other.place,
    );
    if (label == null || label == other.label || !mounted) return;
    await _run(
      () => _controller.updateOther(other.id, label: label),
      'Renamed to "$label"',
    );
  }

  Future<void> _move(OtherSavedPlace other) async {
    final place = await _pickAddress();
    if (place == null || !mounted) return;
    await _run(
      () => _controller.updateOther(other.id, place: place),
      '"${other.label}" updated',
    );
  }

  Future<void> _remove(OtherSavedPlace other) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove "${other.label}"?'),
        content: Text(other.place.address),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => _controller.removeOther(other.id),
      '"${other.label}" removed',
    );
  }

  Future<String?> _askLabel({
    required String title,
    required Place place,
    String? initial,
    String? editingId,
  }) {
    final others =
        ref.read(savedPlacesProvider).value?.others ??
        const <OtherSavedPlace>[];
    final taken = <String>{
      for (final other in others)
        if (other.id != editingId) other.label.toLowerCase(),
    };
    return showDialog<String>(
      context: context,
      builder: (_) => _LabelDialog(
        title: title,
        address: place.address,
        initial: initial,
        taken: taken,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedPlacesProvider);
    final places = saved.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved places'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      floatingActionButton: places == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy || !places.canAddOther ? null : _add,
              backgroundColor: places.canAddOther
                  ? null
                  : AppColors.outlineVariant,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add a place'),
            ),
      body: places == null
          ? (saved.hasError
                ? LoadErrorView(
                    error: saved.error!,
                    onRetry: () => ref.invalidate(savedPlacesProvider),
                  )
                : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: () => ref.refresh(savedPlacesProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  Card(
                    child: Column(
                      children: [
                        for (final kind in SavedPlaceKind.values)
                          _FixedPlaceTile(
                            kind: kind,
                            place: places[kind],
                            enabled: !_busy,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Text(
                          'Your places',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        if (places.others.isNotEmpty)
                          Text(
                            places.canAddOther
                                ? '${places.othersRemaining} more allowed'
                                : 'Limit reached',
                            style: const TextStyle(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (places.others.isEmpty)
                    const _EmptyOthers()
                  else
                    Card(
                      child: Column(
                        children: [
                          for (final other in places.others)
                            _OtherPlaceTile(
                              other: other,
                              enabled: !_busy,
                              onRename: () => _rename(other),
                              onMove: () => _move(other),
                              onRemove: () => _remove(other),
                            ),
                        ],
                      ),
                    ),
                  if (!places.canAddOther)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
                      child: Text(
                        'You have saved the most places allowed. Remove one '
                        'to add another.',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _FixedPlaceTile extends ConsumerWidget {
  const _FixedPlaceTile({
    required this.kind,
    required this.place,
    required this.enabled,
  });

  final SavedPlaceKind kind;
  final Place? place;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = this.place;
    return ListTile(
      enabled: enabled,
      leading: CircleAvatar(
        backgroundColor: AppColors.bhagwaLight,
        child: Icon(savedPlaceIcon(kind), color: AppColors.bhagwaDark),
      ),
      title: Text(kind.label),
      subtitle: Text(
        place?.address ?? 'Add ${kind.label.toLowerCase()} address',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: place == null
            ? const TextStyle(
                color: Color(0xFF2563EB),
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      trailing: place == null
          ? const Icon(Icons.add)
          : IconButton(
              tooltip: '${kind.label} options',
              icon: const Icon(Icons.more_vert),
              onPressed: enabled
                  ? () => showSavedPlaceOptions(context, ref, kind)
                  : null,
            ),
      onTap: () => place == null
          ? context.push(AppRoutes.customerSavePlace(kind.name))
          : showSavedPlaceOptions(context, ref, kind),
    );
  }
}

enum _OtherAction { rename, move, remove }

class _OtherPlaceTile extends StatelessWidget {
  const _OtherPlaceTile({
    required this.other,
    required this.enabled,
    required this.onRename,
    required this.onMove,
    required this.onRemove,
  });

  final OtherSavedPlace other;
  final bool enabled;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFDBEAFE),
        child: Icon(Icons.bookmark_rounded, color: Color(0xFF2563EB)),
      ),
      title: Text(other.label),
      subtitle: Text(
        other.place.address,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: enabled ? onRename : null,
      trailing: PopupMenuButton<_OtherAction>(
        enabled: enabled,
        tooltip: '${other.label} options',
        onSelected: (action) => switch (action) {
          _OtherAction.rename => onRename(),
          _OtherAction.move => onMove(),
          _OtherAction.remove => onRemove(),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _OtherAction.rename,
            child: ListTile(
              leading: Icon(Icons.drive_file_rename_outline),
              title: Text('Rename'),
            ),
          ),
          PopupMenuItem(
            value: _OtherAction.move,
            child: ListTile(
              leading: Icon(Icons.edit_location_alt_outlined),
              title: Text('Change address'),
            ),
          ),
          PopupMenuItem(
            value: _OtherAction.remove,
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('Remove', style: TextStyle(color: AppColors.error)),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyOthers extends StatelessWidget {
  const _EmptyOthers();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.bookmark_add_outlined,
              size: 40,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              'Save the places you go often — your gym, a friend\'s house, '
              'your favourite temple — and book them in one tap.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a place's label. Returns the trimmed label, or null if cancelled.
class _LabelDialog extends StatefulWidget {
  const _LabelDialog({
    required this.title,
    required this.address,
    required this.taken,
    this.initial,
  });

  final String title;
  final String address;
  final Set<String> taken;
  final String? initial;

  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final label = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (label.isEmpty) return 'Give this place a name';
    if (label.length > _maxLabelLength) {
      return 'Use at most $_maxLabelLength characters';
    }
    final key = label.toLowerCase();
    if (key == 'home' || key == 'work') {
      return 'Use the ${key == 'home' ? 'Home' : 'Work'} shortcut instead';
    }
    if (widget.taken.contains(key)) return 'You already have "$label"';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(
      context,
    ).pop(_label.text.trim().replaceAll(RegExp(r'\s+'), ' '));
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _labelSuggestions
        .where((label) => !widget.taken.contains(label.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _label,
              autofocus: true,
              maxLength: _maxLabelLength,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Gym',
                border: OutlineInputBorder(),
              ),
              validator: _validate,
            ),
            if (widget.initial == null && suggestions.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final label in suggestions)
                    ActionChip(
                      label: Text(label),
                      onPressed: () => setState(() => _label.text = label),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
