import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';

class ORSService {
  static const String _baseUrl = 'https://api.openrouteservice.org/v2/directions/driving-car';
  final _apiKey = dotenv.env['ORS_API_KEY'] ?? '';

  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {

    if (_apiKey.isEmpty) {
      print('❌ Error: ORS_API_KEY is missing from .env');
      return [];
    }

    final url = Uri.parse(
        '$_baseUrl?api_key=$_apiKey&start=${start.longitude},${start.latitude}&end=${end.longitude},${end.latitude}');

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
    // Uses the foot-walking profile instead of driving-car
    final String url =
        'https://api.openrouteservice.org/v2/directions/foot-walking?api_key=$_apiKey&start=${start.longitude},${start.latitude}&end=${end.longitude},${end.latitude}';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final summary = data['features'][0]['properties']['summary'];

        return {
          'distance': summary['distance'], // returned in meters
          'duration': summary['duration'], // returned in seconds
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
      'duration': (fallbackDist / 80) * 60, // roughly 80 meters per minute
    };
  }
}