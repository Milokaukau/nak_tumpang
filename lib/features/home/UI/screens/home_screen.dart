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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().fetchMockPassenger();
    });
  }

  @override
  Widget build(BuildContext context) {
    final userName = context.select<HomeViewModel, String?>(
            (viewModel) => viewModel.currentUserName);
    final userRole = context.select<HomeViewModel, String>(
            (viewModel) => viewModel.currentUserRole);

    return Scaffold(
      endDrawer: AppSidebar(
        userName: userName ?? 'Loading...',
        userRole: userRole == 'driver' ? 'Driver' : 'Passenger',
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
          const HomePanel(),
        ],
      ),
    );
  }
}