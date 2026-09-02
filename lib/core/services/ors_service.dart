import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';
import 'package:nak_tumpang/core/constants/api_constants.dart';

class ORSService {
  final _apiKey = dotenv.env['ORS_API_KEY'] ?? '';

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