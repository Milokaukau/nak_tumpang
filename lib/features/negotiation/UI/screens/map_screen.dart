import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:nak_tumpang/core/theme/app_colors.dart';

/// Full-screen map, in two modes:
///
/// - readOnly = true  -> view-only (was FullscreenMapScreen). Just shows the
///   pin, freely pannable/zoomable, no editing UI. Used when viewing an
///   already-accepted location.
/// - readOnly = false -> interactive picker (was LocationPickerScreen). Tap
///   the map or search a store/street name to drop the pin, auto-fills the
///   name via Nominatim reverse geocoding, and returns
///   {'name': String, 'lat': double, 'lng': double} via Navigator.pop when
///   confirmed.
class MapScreen extends StatefulWidget {
  final String title;
  final double initialLat;
  final double initialLng;
  final String initialName;
  final bool readOnly;

  const MapScreen({
    super.key,
    required this.title,
    required this.initialLat,
    required this.initialLng,
    this.initialName = '',
    this.readOnly = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late LatLng _picked;
  late TextEditingController _nameController;
  bool _isLookingUp = false;
  final MapController _mapController = MapController();

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _picked = LatLng(widget.initialLat, widget.initialLng);
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Nominatim's display_name is a long comma-separated full address.
  /// Keep only the first couple of segments so location names stay short
  /// and readable in cards/lists — user can still edit it manually.
  String _shortenAddress(String fullAddress) {
    final parts = fullAddress.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return fullAddress;
    return '${parts[0]}, ${parts[1]}';
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _isLookingUp = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=0',
      );
      final response = await http.get(uri, headers: {'User-Agent': 'com.example.nak_tumpang'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final displayName = data['display_name']?.toString();
        if (displayName != null && mounted) {
          setState(() => _nameController.text = _shortenAddress(displayName));
        }
      }
    } catch (e) {
      debugPrint('Reverse geocode failed: $e');
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  void _onSearchChanged(String query) {
    setState(() {}); // update the clear/loading icon immediately
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchPlace(query);
    });
  }

  Future<void> _searchPlace(String query) async {
    if (query.trim().length < 3) {
      setState(() => _searchResults = []);
      return;
    }
    final int myToken = ++_searchToken;
    setState(() => _isSearching = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeQueryComponent(query)}&limit=6&addressdetails=0',
      );
      final response = await http.get(uri, headers: {'User-Agent': 'com.example.nak_tumpang'});
      if (myToken != _searchToken) return; // a newer search superseded this one
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _searchResults = data
              .map((e) => {
            'display_name': e['display_name'],
            'lat': double.tryParse(e['lat'].toString()) ?? 0.0,
            'lon': double.tryParse(e['lon'].toString()) ?? 0.0,
          })
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Place search failed: $e');
    } finally {
      if (mounted && myToken == _searchToken) setState(() => _isSearching = false);
    }
  }

  void _selectSearchResult(Map<String, dynamic> result) {
    final point = LatLng(result['lat'], result['lon']);
    setState(() {
      _picked = point;
      _nameController.text = _shortenAddress(result['display_name']);
      _searchResults = [];
      _searchController.text = result['display_name'];
    });
    _mapController.move(point, 16.0);
  }

  void _onMapTap(TapPosition tapPos, LatLng point) {
    setState(() {
      _picked = point;
      _searchResults = [];
    });
    _reverseGeocode(point);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        title: Text(
          widget.readOnly ? widget.title : 'Pick ${widget.title}',
          style: const TextStyle(color: AppColors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: widget.readOnly ? _buildReadOnlyMap() : _buildPickerBody(),
    );
  }

  Widget _buildReadOnlyMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _picked,
        initialZoom: 16.0,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.nak_tumpang',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _picked,
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on, color: Colors.red, size: 40),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPickerBody() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _picked,
                  initialZoom: 16.0,
                  onTap: _onMapTap,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.nak_tumpang',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _picked,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Column(
                  children: [
                    Card(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search store or street name',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _isSearching
                              ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                              : (_searchController.text.isNotEmpty
                              ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchResults = []);
                            },
                          )
                              : null),
                        ),
                        onChanged: _onSearchChanged,
                        onSubmitted: _searchPlace,
                      ),
                    ),
                    if (_searchResults.isNotEmpty)
                      Card(
                        margin: const EdgeInsets.only(top: 4),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final result = _searchResults[index];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.location_on, size: 18, color: Colors.red),
                                title: Text(
                                  result['display_name'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                onTap: () => _selectSearchResult(result),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Location Name',
                  border: const OutlineInputBorder(),
                  suffixIcon: _isLookingUp
                      ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryYellow,
                  foregroundColor: AppColors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(context, {
                    'name': _nameController.text.trim().isEmpty
                        ? '${_picked.latitude.toStringAsFixed(5)}, ${_picked.longitude.toStringAsFixed(5)}'
                        : _nameController.text.trim(),
                    'lat': _picked.latitude,
                    'lng': _picked.longitude,
                  });
                },
                child: const Text('Confirm Location', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}