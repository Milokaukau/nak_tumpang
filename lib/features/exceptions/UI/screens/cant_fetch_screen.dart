import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/app_sidebar.dart';
import 'package:nak_tumpang/features/exceptions/view_models/exception_view_model.dart';
import 'package:nak_tumpang/features/exceptions/UI/components/cant_fetch_panel.dart';

class CantFetchScreen extends StatelessWidget {
  final String tumpangSubscriptionId;
  final String driverId;
  final String passengerName;
  final String? passengerImageUrl;
  final String pickupName;
  final String dropoffName;
  final String pickupTime;
  final String passengerPhone;
  final LatLng pickupLatLng;
  final LatLng dropoffLatLng;

  const CantFetchScreen({
    super.key,
    required this.tumpangSubscriptionId,
    required this.driverId,
    required this.passengerName,
    this.passengerImageUrl,
    required this.pickupName,
    required this.dropoffName,
    required this.pickupTime,
    required this.passengerPhone,
    required this.pickupLatLng,
    required this.dropoffLatLng,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ExceptionViewModel(),
      child: Scaffold(
        endDrawer: const AppSidebar(
          userName: 'Loading...',
          userRole: 'Driver',
          selectedIndex: -1,
        ),
        body: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: pickupLatLng,
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.naktumpang.app',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [pickupLatLng, dropoffLatLng],
                      strokeWidth: 4,
                      color: Colors.red,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pickupLatLng,
                      child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                    ),
                  ],
                ),
              ],
            ),
            const Positioned(
              top: 50,
              right: 16,
              child: HamburgerButton(),
            ),
            CantFetchPanel(
              tumpangSubscriptionId: tumpangSubscriptionId,
              driverId: driverId,
              passengerName: passengerName,
              passengerImageUrl: passengerImageUrl,
              pickupName: pickupName,
              dropoffName: dropoffName,
              pickupTime: pickupTime,
              passengerPhone: passengerPhone,
            ),
          ],
        ),
      ),
    );
  }
}