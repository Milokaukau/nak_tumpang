import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/app_sidebar.dart';
import 'package:nak_tumpang/features/home/UI/components/home_panel.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();

    // Trigger the database fetch as soon as the screen renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().fetchMockDriver();
    });
  }

  @override
  Widget build(BuildContext context) {
    // context.select ensures the map only rebuilds if the specific name string changes
    final passengerName = context.select<HomeViewModel, String?>(
            (viewModel) => viewModel.currentPassenger?['name']
    );

    return Scaffold(
      endDrawer: AppSidebar(
        userName: passengerName ?? 'Loading...',
        userRole: 'Passenger',
        selectedIndex: -1,
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(3.2080, 101.7200),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.naktumpang.app',
              ),
            ],
          ),
          const Positioned(
            top: 50,
            right: 16,
            child: HamburgerButton(),
          ),

          // HomePanel handles its own state and UI
          const HomePanel(),
        ],
      ),
    );
  }
}