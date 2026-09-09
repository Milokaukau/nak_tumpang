import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';
import 'package:nak_tumpang/core/constants/api_constants.dart';
import 'package:nak_tumpang/core/entities/geocoded_place.dart';

class ORSService {
  final _apiKey = dotenv.env['ORS_API_KEY'] ?? '';

  /// Resolves free-typed text (e.g. "KLCC", "TARUMT") into real,
  /// selectable places with coordinates, biased to Malaysia. Meant to be
  /// called as the user types (debounce on the caller's side) — this is
  /// the ORS `/geocode/autocomplete` endpoint, which is built for partial
  /// queries, not the heavier `/geocode/search`.
  Future<List<GeocodedPlace>> geocodeAutocomplete(String query) async {
    if (_apiKey.isEmpty) {
      print('❌ Error: ORS_API_KEY is missing from .env');
      return [];
    }
    if (query.trim().isEmpty) return [];

    final url = Uri.parse(
      '${ApiConstants.orsAutocompleteEndpoint}'
          '?api_key=$_apiKey'
          '&text=${Uri.encodeQueryComponent(query.trim())}'
          '&boundary.country=MYS'
          '&size=10',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode != 200) {
        print('ORS Geocode Error: ${response.body}');
        return [];
      }

      final data = json.decode(response.body);
      final features = (data['features'] as List?) ?? [];

      return features
          .map((f) {
        final coords = f['geometry']['coordinates'] as List; // [lng, lat]
        final props = f['properties'] as Map<String, dynamic>;
        return GeocodedPlace(
          label: (props['label'] as String?) ?? query.trim(),
          latitude: (coords[1] as num).toDouble(),
          longitude: (coords[0] as num).toDouble(),
          layer: props['layer'] as String?,
        );
      })
      // Drop seas/oceans/straits etc — "South China Sea" or "Strait of
      // Malacca" are real geocoder results, but never a valid pickup/
      // drop-off point for a trip. Fetched extra above so filtering these
      // out still leaves a full list of real options.
          .where((place) => !place.isWater)
          .take(6)
          .toList();
    } catch (e) {
      print('ORS Geocode Exception: $e');
      return [];
    }
  }

  /// Turns a raw map coordinate (e.g. wherever the user dropped/dragged a
  /// pin) into a human-readable place — the reverse of [geocodeAutocomplete].
  /// Prefers a named venue/POI over a bare street address when one is
  /// close by (the way Grab/Google Maps show "KLCC" instead of "Jalan
  /// Ampang" for the same pin), and falls back to a plain "lat, lng"
  /// label only if nothing is found nearby at all.
  Future<GeocodedPlace> reverseGeocode(LatLng point) async {
    final fallback = GeocodedPlace(
      label: '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
      latitude: point.latitude,
      longitude: point.longitude,
    );

    if (_apiKey.isEmpty) {
      print('❌ Error: ORS_API_KEY is missing from .env');
      return fallback;
    }

    // Try named venues/POIs first (shopping malls, landmarks, campuses,
    // etc.) — only fall back to a plain address if there's no named
    // place close enough to the pin.
    final venue = await _reverseGeocodeQuery(point, layers: 'venue');
    if (venue != null) return venue;

    final address = await _reverseGeocodeQuery(point);
    return address ?? fallback;
  }

  Future<GeocodedPlace?> _reverseGeocodeQuery(LatLng point, {String? layers}) async {
    final url = Uri.parse(
      '${ApiConstants.orsReverseEndpoint}'
          '?api_key=$_apiKey'
          '&point.lat=${point.latitude}'
          '&point.lon=${point.longitude}'
          '&size=1'
          '${layers != null ? '&layers=$layers' : ''}',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode != 200) {
        print('ORS Reverse Geocode Error: ${response.body}');
        return null;
      }

      final data = json.decode(response.body);
      final features = (data['features'] as List?) ?? [];
      if (features.isEmpty) return null;

      final props = features.first['properties'] as Map<String, dynamic>;
      final label = props['label'] as String?;
      if (label == null) return null;

      return GeocodedPlace(
        label: label,
        latitude: point.latitude,
        longitude: point.longitude,
        layer: props['layer'] as String?,
      );
    } catch (e) {
      print('ORS Reverse Geocode Exception: $e');
      return null;
    }
  }

  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    if (_apiKey.isEmpty) {
      print('❌ Error: ORS_API_KEY is missing from .env');
      return [];
    }

    // --- UPDATED to use ApiConstants ---
    final url = Uri.parse(
        '${ApiConstants.orsDrivingEndpoint}?api_key=$_apiKey&start=${start.longitude},${start.latitude}&end=${end.longitude},${end.latitude}');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final coordinates = data['features'][0]['geometry']['coordinates'] as List;

        List<LatLng> route = [];
        for (var coord in coordinates) {
          route.add(LatLng(coord[1], coord[0]));
        }
        return route;
      } else {
        print('ORS Error: ${response.body}');
        return [];
      }
    } catch (e) {
      print('ORS Fetch Exception: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getWalkingMetrics(LatLng start, LatLng end) async {
    // --- FIXED: Removed unnecessary null check since _apiKey defaults to '' ---
    if (_apiKey.isEmpty) {
      print('⚠️ ORS API Key missing. Falling back to default metrics.');
      return {'distance': 0.0, 'duration': 0.0};
    }

    // --- UPDATED to use ApiConstants ---
    final String url =
        '${ApiConstants.orsWalkingEndpoint}?api_key=$_apiKey&start=${start.longitude},${start.latitude}&end=${end.longitude},${end.latitude}';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final summary = data['features'][0]['properties']['summary'];

        return {
          'distance': summary['distance'],
          'duration': summary['duration'],
        };
      }
    } catch (e) {
      print('ORS Walking API Error: $e');
    }

    // Fallback to straight-line math if the API fails
    final fallbackDist = MatchingUtils.calculateDistance(
        start.latitude, start.longitude, end.latitude, end.longitude);
    return {
      'distance': fallbackDist,
      'duration': (fallbackDist / 80) * 60,
    };
  }
}