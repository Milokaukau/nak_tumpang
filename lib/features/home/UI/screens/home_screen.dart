import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nak_tumpang/core/components/app_sidebar.dart';
import 'package:nak_tumpang/features/home/UI/components/home_panel.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: const AppSidebar(
        userName: 'John Cena',
        userRole: 'Driver',
        selectedIndex: -1,
      ),
      body: Stack(
        children: [
          // 1. OpenStreetMap Interactive Background
          FlutterMap(
            options: const MapOptions(
              // Centered near TAR UMT / Setapak area
              initialCenter: LatLng(3.2080, 101.7200),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                // The free OpenStreetMap tile server URL
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                // OSM requires a user agent to prevent abuse of their free tier
                userAgentPackageName: 'com.naktumpang.app',
              ),
            ],
          ),

          // 2. Reusable Floating Hamburger Menu Button
          const Positioned(
            top: 50,
            right: 16,
            child: HamburgerButton(),
          ),

          // 3. Sliding Panel
          const HomePanel(),
        ],
      ),
    );
  }
}