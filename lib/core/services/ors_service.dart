import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ORSService {
  static const String _baseUrl = 'https://api.openrouteservice.org/v2/directions/driving-car';

  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    // Read the key from the .env file
    final apiKey = dotenv.env['ORS_API_KEY'] ?? '';

    if (apiKey.isEmpty) {
      print('❌ Error: ORS_API_KEY is missing from .env');
      return [];
    }

    final url = Uri.parse(
        '$_baseUrl?api_key=$apiKey&start=${start.longitude},${start.latitude}&end=${end.longitude},${end.latitude}');

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
}