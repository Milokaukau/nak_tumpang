import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class SummaryRouteMap extends StatelessWidget {
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;

  const SummaryRouteMap({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
  });

  @override
  Widget build(BuildContext context) {
    final pickup = LatLng(pickupLat, pickupLng);
    final dropoff = LatLng(dropoffLat, dropoffLng);

    final bounds = LatLngBounds.fromPoints([pickup, dropoff]);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(32.0),
          ),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.nak_tumpang',
          ),
          PolylineLayer(
            polylines: [
              Polyline(points: [pickup, dropoff], strokeWidth: 4.0, color: Colors.redAccent),
            ],
          ),
          MarkerLayer(
            markers: [
              Marker(point: pickup, width: 40, height: 40, child: const Icon(Icons.location_on, color: Colors.red, size: 40)),
              Marker(point: dropoff, width: 40, height: 40, child: const Icon(Icons.location_on, color: Colors.red, size: 40)),
            ],
          ),
        ],
      ),
    );
  }
}