import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

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

  void _openFullScreenMap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Route Overview', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
            backgroundColor: AppColors.primaryYellow,
            iconTheme: const IconThemeData(color: AppColors.black),
          ),
          body: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(
                (pickupLat + dropoffLat) / 2,
                (pickupLng + dropoffLng) / 2,
              ),
              initialZoom: 13.0,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.nak_tumpang',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [LatLng(pickupLat, pickupLng), LatLng(dropoffLat, dropoffLng)],
                    strokeWidth: 4.0,
                    color: Colors.blueAccent,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(point: LatLng(pickupLat, pickupLng), child: const Icon(Icons.location_on, color: Colors.green, size: 40)),
                  Marker(point: LatLng(dropoffLat, dropoffLng), child: const Icon(Icons.location_on, color: Colors.red, size: 40)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openFullScreenMap(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: LatLng((pickupLat + dropoffLat) / 2, (pickupLng + dropoffLng) / 2),
                initialZoom: 12.0,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none), // Static preview
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.nak_tumpang'),
                PolylineLayer(
                  polylines: [Polyline(points: [LatLng(pickupLat, pickupLng), LatLng(dropoffLat, dropoffLng)], strokeWidth: 3.0, color: Colors.blueAccent)],
                ),
                MarkerLayer(
                  markers: [
                    Marker(point: LatLng(pickupLat, pickupLng), child: const Icon(Icons.location_on, color: Colors.green, size: 30)),
                    Marker(point: LatLng(dropoffLat, dropoffLng), child: const Icon(Icons.location_on, color: Colors.red, size: 30)),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle),
                child: const Icon(Icons.fullscreen, size: 20, color: AppColors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}