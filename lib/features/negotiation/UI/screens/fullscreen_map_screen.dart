import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class FullscreenMapScreen extends StatelessWidget {
  final String label;
  final double lat;
  final double lng;

  const FullscreenMapScreen({
    super.key,
    required this.label,
    required this.lat,
    required this.lng,
  });

  @override
  Widget build(BuildContext context) {
    final location = LatLng(lat, lng);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        title: Text(label, style: const TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: location,
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
                point: location,
                width: 40,
                height: 40,
                child: const Icon(Icons.location_on, color: Colors.red, size: 40),
              ),
            ],
          ),
        ],
      ),
    );
  }
}