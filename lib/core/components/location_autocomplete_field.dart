import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/components/location_picker_screen.dart';
import 'package:nak_tumpang/core/entities/geocoded_place.dart';
import 'package:nak_tumpang/core/services/ors_service.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/utils/geo_bounds.dart';

// text = real place with coordinates  via ORS geocoding
// shows real place name, not just coordinates
// also allow pick on map option
class LocationAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<GeocodedPlace> onSelected;
  final VoidCallback? onCleared;

  final String? mapPickerTitle;

  const LocationAutocompleteField({
    super.key,
    required this.controller,
    required this.onSelected,
    this.hintText = 'Search for a place or address',
    this.onCleared,
    this.mapPickerTitle,
  });

  @override
  State<LocationAutocompleteField> createState() => _LocationAutocompleteFieldState();
}

class _LocationAutocompleteFieldState extends State<LocationAutocompleteField> {
  final _ors = ORSService();
  Timer? _debounce;
  List<GeocodedPlace> _suggestions = [];
  bool _isSearching = false;

  // next search suppressed when a suggestion is selected
  bool _suppressNextSearch = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String text) {
    widget.onCleared?.call();
    _debounce?.cancel();

    if (_suppressNextSearch) {
      _suppressNextSearch = false;
      return;
    }

    if (text.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _isSearching = true);
      final results = await _ors.geocodeAutocomplete(text);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _isSearching = false;
      });
    });
  }

  void _select(GeocodedPlace place) {
    // text search only find within malaysia and no ocean/sea results
    // map picker can hand back a place
    if (!MalaysiaBounds.contains(place.latitude, place.longitude)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(MalaysiaBounds.outsideMessage)));
      setState(() => _suggestions = []);
      return;
    }
    if (place.isWater) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text("Please pick a location on land — sea and ocean locations aren't allowed.")));
      setState(() => _suggestions = []);
      return;
    }

    _suppressNextSearch = true;
    widget.controller.value = TextEditingValue(
      text: place.label,
      selection: TextSelection.collapsed(offset: place.label.length),
    );
    setState(() => _suggestions = []);
    FocusScope.of(context).unfocus();
    widget.onSelected(place);
  }

  Future<void> _openMapPicker() async {
    FocusScope.of(context).unfocus();
    final place = await LocationPickerScreen.show(
      context,
      title: widget.mapPickerTitle ?? widget.hintText,
      initialQuery: widget.controller.text,
    );
    if (place != null) _select(place);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(color: AppColors.greyText.withValues(alpha: 0.6)),
            suffixIcon: _isSearching
                ? const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
                : IconButton(
              tooltip: 'Pick on map',
              icon: const Icon(Icons.map_outlined, color: AppColors.primaryYellow),
              onPressed: _openMapPicker,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.greyBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.greyBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primaryYellow, width: 1.5),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.greyBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.greyBorder),
              itemBuilder: (context, i) {
                final place = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, size: 18, color: AppColors.greyText),
                  title: Text(place.label, style: const TextStyle(fontSize: 13)),
                  onTap: () => _select(place),
                );
              },
            ),
          ),
      ],
    );
  }
}