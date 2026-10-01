import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/location/driver_fix.dart' show distanceMeters;
import '../../../core/theme/app_colors.dart';
import '../../rides/application/booking_controller.dart';
import '../../rides/domain/ride_models.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';
import '../application/current_location.dart';
import '../application/place_search_controller.dart';
import '../application/popular_places.dart';
import '../application/recent_places.dart';
import '../application/saved_places.dart';
import '../application/voice_search.dart';
import '../domain/place_suggestion.dart';
import '../domain/saved_place.dart';
import 'location_feedback.dart';
import 'saved_place_actions.dart';

/// Pickup and destination closer than this are treated as the same place.
const _samePlaceMeters = 50.0;

/// Recent destinations shown before "See all".
const _recentPreviewCount = 4;

/// "Where to?": search as you type (or speak), saved Home/Work, recent and
/// popular destinations, and "Choose on map" pinned at the bottom.
///
/// With [pickOnly] set it only chooses an address and returns it (the
/// caller decides what to do with it, e.g. save one of the rider's own
/// places).
///
/// With [saveAs] set the screen picks an address for the rider's Home or
/// Work instead of the trip: the chosen place is saved and returned.
class LocationSearchScreen extends ConsumerStatefulWidget {
  const LocationSearchScreen({
    super.key,
    required this.initialField,
    this.saveAs,
    this.pickOnly = false,
  });

  final PlaceField initialField;
  final SavedPlaceKind? saveAs;
  final bool pickOnly;

  @override
  ConsumerState<LocationSearchScreen> createState() =>
      _LocationSearchScreenState();
}

class _LocationSearchScreenState extends ConsumerState<LocationSearchScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'search_field');
  late PlaceField _active = widget.initialField;

  /// Resolving a tapped suggestion, locating the device or saving.
  bool _busy = false;
  bool _listening = false;

  /// Choosing an address for somewhere other than the current trip.
  bool get _savingAddress => widget.saveAs != null || widget.pickOnly;

  Place? _placeFor(PlaceField field) {
    final booking = ref.read(bookingControllerProvider);
    return field == PlaceField.pickup ? booking.pickup : booking.destination;
  }

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    final committed = _savingAddress
        ? ''
        : _placeFor(widget.initialField)?.title ?? '';
    _searchController.text = committed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      if (committed.isNotEmpty) {
        _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: committed.length,
        );
      }
    });
  }

  @override
  void dispose() {
    if (_listening) unawaited(ref.read(voiceSearchProvider).stop());
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    ref.read(placeSearchControllerProvider.notifier).search(value);
    setState(() {});
  }

  void _switchField(PlaceField field) {
    setState(() {
      _active = field;
      _searchController.text = _placeFor(field)?.title ?? '';
    });
    ref.read(placeSearchControllerProvider.notifier).clear();
    _searchFocus.requestFocus();
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    if (_busy) return;
    final field = _active;
    setState(() => _busy = true);
    try {
      final place = await ref
          .read(placeSearchControllerProvider.notifier)
          .choose(suggestion);
      if (mounted) await _apply(field, place);
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_busy) return;
    final field = _active;
    setState(() => _busy = true);
    try {
      final place = await ref.read(currentPlaceLocatorProvider).locate();
      if (mounted) await _apply(field, place, remember: false);
    } on Object catch (error) {
      if (mounted) showLocationError(context, ref, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickOnMap() async {
    final field = _active;
    FocusScope.of(context).unfocus();
    final place = await context.push<Place>(
      AppRoutes.customerMapPickerFor(field.name),
    );
    if (place != null && mounted) await _apply(field, place);
  }

  /// Saving an address: stores it and returns it. Booking: sets [field],
  /// then moves on to the other field if it is still empty, else to ride
  /// options.
  Future<void> _apply(
    PlaceField field,
    Place place, {
    bool remember = true,
  }) async {
    if (widget.pickOnly) {
      context.pop(place);
      return;
    }
    final saveAs = widget.saveAs;
    if (saveAs != null) {
      await _saveAddress(saveAs, place);
      return;
    }

    final booking = ref.read(bookingControllerProvider);
    final other = field == PlaceField.pickup
        ? booking.destination
        : booking.pickup;
    if (other != null &&
        distanceMeters(
              other.latitude,
              other.longitude,
              place.latitude,
              place.longitude,
            ) <
            _samePlaceMeters) {
      showErrorSnack(
        context,
        const UserFacingError(
          'Pickup and destination can\'t be the same place.',
        ),
      );
      return;
    }

    final controller = ref.read(bookingControllerProvider.notifier);
    if (field == PlaceField.pickup) {
      controller.setPickup(place, remember: remember);
    } else {
      controller.setDestination(place, remember: remember);
    }
    _searchController.text = place.title;

    final next = ref.read(bookingControllerProvider);
    if (next.pickup == null) {
      _switchField(PlaceField.pickup);
    } else if (next.destination == null) {
      _switchField(PlaceField.destination);
    } else {
      _continue();
    }
  }

  Future<void> _saveAddress(SavedPlaceKind kind, Place place) async {
    setState(() => _busy = true);
    try {
      await ref.read(savedPlacesProvider.notifier).save(kind, place);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${kind.label} saved: ${place.title}')),
      );
      context.pop(place);
    } on Object catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continue() {
    FocusScope.of(context).unfocus();
    final controller = ref.read(bookingControllerProvider.notifier);
    unawaited(controller.loadEstimates());
    context.pushReplacement(AppRoutes.customerRideOptions);
  }

  void _clearSearch() {
    _searchController.clear();
    _onChanged('');
    _searchFocus.requestFocus();
  }

  Future<void> _toggleVoiceSearch() async {
    final voice = ref.read(voiceSearchProvider);
    if (_listening) {
      await voice.stop();
      return;
    }
    setState(() => _listening = true);
    try {
      await voice.listen(
        onWords: (words, {required isFinal}) {
          if (!mounted || words.isEmpty) return;
          _searchController.value = TextEditingValue(
            text: words,
            selection: TextSelection.collapsed(offset: words.length),
          );
          _onChanged(words);
        },
        onDone: () {
          if (mounted) setState(() => _listening = false);
        },
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _listening = false);
      showErrorSnack(
        context,
        error is VoiceSearchUnavailable
            ? UserFacingError(error.message)
            : const UserFacingError(
                'Voice search is not available right now. '
                'Please type the place instead.',
              ),
      );
    }
  }

  Future<void> _openSavedPlace(SavedPlaceKind kind, Place? saved) async {
    if (saved != null) {
      await _apply(_active, saved);
      return;
    }
    await context.push(AppRoutes.customerSavePlace(kind.name));
    _resyncSearch();
  }

  Future<void> _savedPlaceOptions(SavedPlaceKind kind) async {
    await showSavedPlaceOptions(context, ref, kind);
    _resyncSearch();
  }

  /// The search state is shared with a pushed "Set home address" screen;
  /// back here it must reflect this screen's box again.
  void _resyncSearch() {
    if (!mounted) return;
    ref
        .read(placeSearchControllerProvider.notifier)
        .search(_searchController.text);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(placeSearchControllerProvider);
    final booking = ref.watch(bookingControllerProvider);
    final showProgress = _busy || (search.loading && search.isSearching);

    final saveAs = widget.saveAs;
    final titleText = widget.pickOnly
        ? 'Choose an address'
        : saveAs != null
        ? 'Set ${saveAs.label.toLowerCase()} address'
        : _active == PlaceField.pickup
        ? 'Pickup location'
        : 'Where to?';
    final hintText = widget.pickOnly
        ? 'Search for a place'
        : saveAs != null
        ? 'Search ${saveAs.label.toLowerCase()} address'
        : _active == PlaceField.pickup
        ? 'Search pickup location'
        : 'Search destination';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back, color: _ink, size: 22),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 4,
        title: Text(
          titleText,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: _ink,
            letterSpacing: -0.2,
          ),
        ),
        bottom: showProgress
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: const LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.bhagwa,
                  backgroundColor: AppColors.bhagwaLight,
                ),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: _SearchField(
                controller: _searchController,
                focusNode: _searchFocus,
                hintText: hintText,
                listening: _listening,
                onChanged: _onChanged,
                onClear: _clearSearch,
                onVoice: () => unawaited(_toggleVoiceSearch()),
              ),
            ),
            Expanded(
              child: search.isSearching
                  ? _SearchResults(
                      state: search,
                      enabled: !_busy,
                      onSelect: _select,
                      onPickOnMap: _pickOnMap,
                      onRetry: () => unawaited(
                        ref
                            .read(placeSearchControllerProvider.notifier)
                            .retry(),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: _Suggestions(
                            field: _active,
                            savingAddress: _savingAddress,
                            enabled: !_busy,
                            exclude: _savingAddress
                                ? null
                                : _active == PlaceField.pickup
                                ? booking.destination
                                : booking.pickup,
                            onUseCurrentLocation: _useCurrentLocation,
                            onSelectPlace: (place) =>
                                unawaited(_apply(_active, place)),
                            onOpenSavedPlace: (kind, saved) =>
                                unawaited(_openSavedPlace(kind, saved)),
                            onSavedPlaceOptions: (kind) =>
                                unawaited(_savedPlaceOptions(kind)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                          child: _ChooseOnMapCard(onTap: _pickOnMap),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

const _ink = AppColors.midnightBlue;
const _muted = AppColors.onSurfaceVariant;
const _faint = AppColors.outlineVariant;
const _blue = AppColors.bhagwa;
const _divider = Color(0xFFE2E8F0);

// ─────────────────────────────────────────────────────────────────────────────
// Search field (with clear and voice)
// ─────────────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.listening,
    required this.onChanged,
    required this.onClear,
    required this.onVoice,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final bool listening;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focusNode.hasFocus ? _blue : _divider,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search_rounded, color: _muted, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.words,
              autocorrect: false,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _ink,
              ),
              decoration: InputDecoration(
                hintText: listening ? 'Listening… say a place' : hintText,
                hintStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: _muted,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                isDense: true,
              ),
            ),
          ),
          if (controller.text.isNotEmpty && !listening)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close, color: _muted, size: 18),
              onPressed: onClear,
            ),
          IconButton(
            tooltip: listening ? 'Stop listening' : 'Search by voice',
            onPressed: onVoice,
            icon: listening
                ? const _ListeningMic()
                : const Icon(Icons.mic_rounded, color: Color(0xFF475569)),
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

class _ListeningMic extends StatelessWidget {
  const _ListeningMic();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 16),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Before typing: saved, recent and popular places
// ─────────────────────────────────────────────────────────────────────────────

class _Suggestions extends ConsumerStatefulWidget {
  const _Suggestions({
    required this.field,
    required this.savingAddress,
    required this.enabled,
    required this.exclude,
    required this.onUseCurrentLocation,
    required this.onSelectPlace,
    required this.onOpenSavedPlace,
    required this.onSavedPlaceOptions,
  });

  final PlaceField field;
  final bool savingAddress;
  final bool enabled;
  final Place? exclude;
  final VoidCallback onUseCurrentLocation;
  final ValueChanged<Place> onSelectPlace;
  final void Function(SavedPlaceKind kind, Place? saved) onOpenSavedPlace;
  final ValueChanged<SavedPlaceKind> onSavedPlaceOptions;

  @override
  ConsumerState<_Suggestions> createState() => _SuggestionsState();
}

class _SuggestionsState extends ConsumerState<_Suggestions> {
  bool _showAllRecent = false;

  /// The rider's own labelled places, named by their label ("Gym").
  List<Widget> _otherSavedPlaces(List<OtherSavedPlace> others) {
    final usable = others
        .where(
          (other) => !_excluded(other.place.latitude, other.place.longitude),
        )
        .toList();
    if (usable.isEmpty) return const [];
    return [
      const _SectionHeader(title: 'Your places'),
      for (final (index, other) in usable.indexed)
        _PlaceRow(
          leading: Icons.bookmark_rounded,
          trailing: Icons.north_west_rounded,
          place: Place(
            name: other.label,
            address: other.place.address,
            latitude: other.place.latitude,
            longitude: other.place.longitude,
          ),
          enabled: widget.enabled,
          divider: index < usable.length - 1,
          onTap: () => widget.onSelectPlace(other.place),
        ),
      const SizedBox(height: 14),
    ];
  }

  bool _excluded(double latitude, double longitude) {
    final other = widget.exclude;
    return other != null &&
        distanceMeters(other.latitude, other.longitude, latitude, longitude) <
            _samePlaceMeters;
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedPlacesProvider);
    final recent = (ref.watch(recentDestinationsProvider).value ?? const [])
        .where((place) => !_excluded(place.latitude, place.longitude))
        .toList();
    final popular = ref.watch(popularPlacesProvider);
    final visibleRecent = _showAllRecent
        ? recent
        : recent.take(_recentPreviewCount).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        // Standing still is the usual pickup, rarely the destination.
        if (widget.field == PlaceField.pickup || widget.savingAddress) ...[
          _ActionTile(
            icon: Icons.my_location,
            title: 'Use current location',
            subtitle: widget.savingAddress
                ? 'Save where you are right now'
                : 'Get picked up where you are',
            enabled: widget.enabled,
            onTap: widget.onUseCurrentLocation,
          ),
          const SizedBox(height: 4),
        ],

        if (!widget.savingAddress) ...[
          Row(
            children: [
              for (final kind in SavedPlaceKind.values) ...[
                if (kind != SavedPlaceKind.values.first)
                  const SizedBox(width: 8),
                Expanded(
                  child: SavedPlaceCard(
                    kind: kind,
                    saved: saved.value?[kind],
                    loading: saved.isLoading,
                    onTap: () =>
                        widget.onOpenSavedPlace(kind, saved.value?[kind]),
                    onLongPress: saved.value?[kind] == null
                        ? null
                        : () => widget.onSavedPlaceOptions(kind),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          ..._otherSavedPlaces(saved.value?.others ?? const []),
        ],

        if (recent.isNotEmpty) ...[
          _SectionHeader(
            title: 'Recent destinations',
            action: recent.length > _recentPreviewCount
                ? (_showAllRecent ? 'Show less' : 'See all')
                : null,
            onAction: () => setState(() => _showAllRecent = !_showAllRecent),
          ),
          for (final (index, place) in visibleRecent.indexed)
            _PlaceRow(
              leading: Icons.schedule_rounded,
              trailing: Icons.north_west_rounded,
              place: place,
              enabled: widget.enabled,
              divider: index < visibleRecent.length - 1,
              onTap: () => widget.onSelectPlace(place),
              onLongPress: () => _confirmForget(place),
            ),
          const SizedBox(height: 14),
        ],

        ...popular.when(
          data: (places) {
            final visible = places
                .where(
                  (place) =>
                      place.hasCoordinates &&
                      !_excluded(place.latitude!, place.longitude!),
                )
                .toList();
            if (visible.isEmpty) return const <Widget>[];
            return [
              const _SectionHeader(title: 'Popular destinations'),
              for (final (index, suggestion) in visible.indexed)
                _PlaceRow(
                  leading: Icons.location_on_outlined,
                  trailing: Icons.chevron_right_rounded,
                  place: suggestion.toPlace(),
                  subtitle: suggestion.secondaryText,
                  enabled: widget.enabled,
                  divider: index < visible.length - 1,
                  onTap: () => widget.onSelectPlace(suggestion.toPlace()),
                ),
            ];
          },
          loading: () => const [
            Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ],
          // Optional section: search and the map still work.
          error: (_, _) => const <Widget>[],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _confirmForget(Place place) async {
    final forget = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from recent?'),
        content: Text(place.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (forget ?? false) {
      await ref.read(recentPlacesProvider.notifier).forget(place);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: _blue,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

/// A recent or popular destination: icon, title, locality, trailing arrow,
/// and a hairline divider aligned with the text.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.leading,
    required this.trailing,
    required this.place,
    required this.enabled,
    required this.divider,
    required this.onTap,
    this.subtitle,
    this.onLongPress,
  });

  final IconData leading;
  final IconData trailing;
  final Place place;
  final String? subtitle;
  final bool enabled;
  final bool divider;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// "Sector 18, Noida" for "DLF Mall of India, Sector 18, Noida".
  String? get _secondLine {
    if (subtitle != null && subtitle!.isNotEmpty) return subtitle;
    final name = place.name;
    if (name == null || name == place.address) return null;
    final rest = place.address.startsWith('$name,')
        ? place.address.substring(name.length + 1).trim()
        : place.address;
    return rest.isEmpty ? null : rest;
  }

  @override
  Widget build(BuildContext context) {
    final second = _secondLine;
    return InkWell(
      onTap: enabled ? onTap : null,
      onLongPress: onLongPress,
      child: Row(
        children: [
          SizedBox(width: 30, child: Icon(leading, color: _muted, size: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: divider
                    ? const Border(bottom: BorderSide(color: _divider))
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: _ink,
                            ),
                          ),
                          if (second != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              second,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(trailing, size: 18, color: _faint),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Choose on map" card pinned under the list
// ─────────────────────────────────────────────────────────────────────────────

class _ChooseOnMapCard extends StatelessWidget {
  const _ChooseOnMapCard({
    required this.onTap,
    this.subtitle = 'Tap to select a location',
  });

  final VoidCallback onTap;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.midnightBlue,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.map_outlined, color: AppColors.sacredGold, size: 22),
              const SizedBox(width: 12),
              Container(width: 1, height: 26, color: AppColors.outlineVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Choose on map',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: AppColors.outlineVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.sacredGold, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// While typing: live autocomplete results
// ─────────────────────────────────────────────────────────────────────────────

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.state,
    required this.enabled,
    required this.onSelect,
    required this.onPickOnMap,
    required this.onRetry,
  });

  final PlaceSearchState state;
  final bool enabled;
  final ValueChanged<PlaceSuggestion> onSelect;
  final VoidCallback onPickOnMap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final suggestions = state.suggestions;
    final mapTile = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: _ChooseOnMapCard(
        subtitle: "Can't find it? Drop a pin instead",
        onTap: onPickOnMap,
      ),
    );

    if (state.error != null) {
      return ListView(
        children: [
          _Notice(
            icon: Icons.cloud_off_outlined,
            message: errorMessage(state.error!),
            action: TextButton(onPressed: onRetry, child: const Text('Retry')),
          ),
          mapTile,
        ],
      );
    }
    if (suggestions == null) return const SizedBox.shrink();

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (state.degraded)
          _Notice(
            icon: Icons.info_outline,
            message:
                'Full search is unavailable right now, so only popular '
                'places are shown. You can also set the location on the map.',
            action: state.loading
                ? null
                : TextButton(onPressed: onRetry, child: const Text('Retry')),
          ),
        if (suggestions.isEmpty && !state.loading)
          _Notice(
            icon: Icons.search_off,
            message: 'No places match "${state.query}".',
          ),
        for (final suggestion in suggestions)
          _SuggestionTile(
            suggestion: suggestion,
            enabled: enabled,
            onTap: () => onSelect(suggestion),
          ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        mapTile,
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.enabled,
    required this.onTap,
  });

  final PlaceSuggestion suggestion;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final distance = suggestion.distanceMeters;
    return ListTile(
      enabled: enabled,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: const Color(0xFFF1F5F9),
        child: Icon(
          suggestion.featured ? Icons.temple_hindu : Icons.place_outlined,
          size: 17,
          color: const Color(0xFF475569),
        ),
      ),
      title: Text(
        suggestion.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: _ink,
          fontSize: 14,
        ),
      ),
      subtitle: suggestion.secondaryText.isEmpty
          ? null
          : Text(
              suggestion.secondaryText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
      trailing: distance == null
          ? null
          : Text(
              formatDistance(distance),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _muted,
              ),
            ),
      onTap: onTap,
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        radius: 15,
        backgroundColor: Color(0xFFEFF6FF),
        child: Icon(Icons.my_location, size: 17, color: _blue),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: _ink,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: _muted),
      ),
      onTap: onTap,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
