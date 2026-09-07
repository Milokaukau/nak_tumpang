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

    // AuthGate rebuilds HomeScreen fresh each time a session starts, so
    // this fires once per real login — fetching the actual signed-in
    // user's role/data instead of a hardcoded mock ID.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().fetchCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    // context.select ensures the map only rebuilds if the specific name string changes
    final displayName = context.select<HomeViewModel, String?>(
            (viewModel) => viewModel.currentUserName ?? viewModel.currentPassenger?['name']
    );
    // Pull the real role from the view model instead of assuming 'Passenger' —
    // currentUserRole is set to the actual signed-in user's role by fetchCurrentUser().
    final currentUserRole = context.select<HomeViewModel, String>(
            (viewModel) => viewModel.currentUserRole
    );
    final displayRole = currentUserRole.isEmpty
        ? 'Passenger'
        : currentUserRole[0].toUpperCase() + currentUserRole.substring(1);

    return Scaffold(
      endDrawer: AppSidebar(
        userName: displayName ?? 'Loading...',
        userRole: displayRole,
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