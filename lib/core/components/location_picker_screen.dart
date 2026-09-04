import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:nak_tumpang/core/entities/geocoded_place.dart';
import 'package:nak_tumpang/core/services/ors_service.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/utils/geo_bounds.dart';

/// Full-screen "pick a location" experience, similar to Grab/Google Maps:
/// search for a place and pick it from a dropdown, or tap anywhere on the
/// map to drop a pin there. Push it with [LocationPickerScreen.show] and
/// await the [GeocodedPlace] the user confirms (or null if they back out).
class LocationPickerScreen extends StatefulWidget {
  final String title;
  final String? initialQuery;

  const LocationPickerScreen({super.key, required this.title, this.initialQuery});

  static Future<GeocodedPlace?> show(
      BuildContext context, {
        required String title,
        String? initialQuery,
      }) {
    return Navigator.of(context).push<GeocodedPlace>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(title: title, initialQuery: initialQuery),
      ),
    );
  }

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Kuala Lumpur — sensible default center until the user searches or taps.
  static const _defaultCenter = LatLng(3.1390, 101.6869);

  final _ors = ORSService();
  final _mapController = MapController();
  late final _searchController = TextEditingController(text: widget.initialQuery ?? '');

  Timer? _debounce;
  List<GeocodedPlace> _suggestions = [];
  bool _isSearching = false;
  bool _isResolvingTap = false;
  bool _isLocatingMe = false;
  GeocodedPlace? _selectedPlace;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
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

  void _showOutsideMalaysiaError() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(MalaysiaBounds.outsideMessage)));
  }

  void _showWaterError() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Please pick a valid location.')));
  }

  void _pickSuggestion(GeocodedPlace place) {
    FocusScope.of(context).unfocus();
    if (!MalaysiaBounds.contains(place.latitude, place.longitude)) {
      setState(() => _suggestions = []);
      _showOutsideMalaysiaError();
      return;
    }
    if (place.isWater) {
      setState(() => _suggestions = []);
      _showWaterError();
      return;
    }
    setState(() {
      _selectedPlace = place;
      _suggestions = [];
      _searchController.text = place.label;
    });
    _mapController.move(LatLng(place.latitude, place.longitude), 16);
  }

  Future<void> _onMapTapped(TapPosition tapPosition, LatLng point) async {
    FocusScope.of(context).unfocus();

    if (!MalaysiaBounds.contains(point.latitude, point.longitude)) {
      setState(() => _suggestions = []);
      _showOutsideMalaysiaError();
      return;
    }

    setState(() {
      _suggestions = [];
      _isResolvingTap = true;
      _selectedPlace = GeocodedPlace(label: 'Finding address...', latitude: point.latitude, longitude: point.longitude);
    });

    final place = await _ors.reverseGeocode(point);
    if (!mounted) return;

    // A point can be well within Malaysia's bounding box and still be
    // sea (e.g. the Strait of Malacca) — the box alone can't tell,
    // only the geocoder's result can, so this check has to happen here.
    if (place.isWater) {
      setState(() {
        _selectedPlace = null;
        _isResolvingTap = false;
      });
      _showWaterError();
      return;
    }

    setState(() {
      _selectedPlace = place;
      _searchController.text = place.label;
      _isResolvingTap = false;
    });
  }

  /// "Use my location" — Grab/Google-Maps style GPS button. Requests
  /// permission if needed, reverse-geocodes the current fix into a named
  /// place, and centers the map on it. Rejected the same way a map tap
  /// outside Malaysia would be.
  Future<void> _useMyLocation() async {
    setState(() => _isLocatingMe = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Location permission is needed to use your current location.')));
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Please turn on location services.')));
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;

      if (!MalaysiaBounds.contains(position.latitude, position.longitude)) {
        _showOutsideMalaysiaError();
        return;
      }

      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _suggestions = [];
        _isResolvingTap = true;
        _selectedPlace = GeocodedPlace(label: 'Finding address...', latitude: point.latitude, longitude: point.longitude);
      });
      _mapController.move(point, 16);

      final place = await _ors.reverseGeocode(point);
      if (!mounted) return;

      if (place.isWater) {
        setState(() {
          _selectedPlace = null;
          _isResolvingTap = false;
        });
        _showWaterError();
        return;
      }

      setState(() {
        _selectedPlace = place;
        _searchController.text = place.label;
        _isResolvingTap = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not get your current location.')));
    } finally {
      if (mounted) setState(() => _isLocatingMe = false);
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _suggestions = [];
    });
  }

  void _confirm() {
    if (_selectedPlace == null || _isResolvingTap) return;
    Navigator.of(context).pop(_selectedPlace);
  }

  @override
  Widget build(BuildContext context) {
    final markerPoint =
    _selectedPlace != null ? LatLng(_selectedPlace!.latitude, _selectedPlace!.longitude) : null;

    return Scaffold(
      backgroundColor: AppColors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: markerPoint ?? _defaultCenter,
              initialZoom: markerPoint != null ? 16 : 12,
              onTap: _onMapTapped,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.naktumpang.app',
              ),
              if (markerPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: markerPoint,
                      width: 44,
                      height: 44,
                      child: Icon(Icons.location_on, color: AppColors.primaryYellow, size: 44),
                    ),
                  ],
                ),
            ],
          ),

          // Back button + search bar, with suggestions dropdown below it.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _RoundIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            autofocus: widget.initialQuery == null || widget.initialQuery!.isEmpty,
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: widget.title,
                              hintStyle: TextStyle(color: AppColors.greyText.withValues(alpha: 0.6)),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              suffixIcon: _isSearching
                                  ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                                  : (_searchController.text.isNotEmpty
                                  ? IconButton(
                                icon: const Icon(Icons.clear, size: 18, color: AppColors.greyText),
                                onPressed: _clearSearch,
                              )
                                  : const Icon(Icons.search, color: AppColors.greyText)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 280),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
                        ],
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
                            onTap: () => _pickSuggestion(place),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // "Use my location" FAB, floating just above the confirm card.
          Positioned(
            right: 16,
            bottom: 190,
            child: SafeArea(
              top: false,
              child: Material(
                color: AppColors.white,
                shape: const CircleBorder(),
                elevation: 3,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _isLocatingMe ? null : _useMyLocation,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _isLocatingMe
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Icon(Icons.my_location, color: AppColors.primaryYellow, size: 20),
                  ),
                ),
              ),
            ),
          ),

          // Selected place + confirm button, pinned to the bottom.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_on, color: AppColors.primaryYellow, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedPlace?.label ?? 'Search above or tap the map to choose a location',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: _selectedPlace == null ? AppColors.greyText : AppColors.black,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryYellow,
                          disabledBackgroundColor: AppColors.primaryYellow.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        onPressed: (_selectedPlace == null || _isResolvingTap) ? null : _confirm,
                        child: Text(
                          'Confirm Location',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
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

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: AppColors.black),
        ),
      ),
    );
  }
}
