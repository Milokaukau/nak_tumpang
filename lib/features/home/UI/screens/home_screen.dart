import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nak_tumpang/core/components/map_pin.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/app_sidebar.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/home/UI/components/home_panel.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();
  LatLng? _lastStartLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().fetchMockPassenger();
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();
    final passengerName = viewModel.currentPassenger?['name'] ?? 'Loading...';

    final currentStart = viewModel.routeStart;

    // Relocate map camera when the start location changes
    if (currentStart != null && currentStart != _lastStartLocation) {
      _lastStartLocation = currentStart;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(currentStart, 16.0);
      });
    }

    final initialCenter = currentStart ?? const LatLng(3.1578, 101.7118);

    return Scaffold(
      endDrawer: AppSidebar(
        userName: passengerName,
        userRole: 'Passenger',
        selectedIndex: -1,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 16.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.naktumpang.app',
              ),
              PolylineLayer(
                polylines: [
                  if (viewModel.mapRoute.isNotEmpty)
                    Polyline(
                      points: viewModel.displayRoute,
                      strokeWidth: 5.0,
                      color: Colors.blueAccent,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (viewModel.routeStart != null)
                    Marker(
                      point: viewModel.routeStart!,
                      width: 32,
                      height: 40,
                      alignment: Alignment.bottomCenter,
                      child: const MapPin(color: Colors.green),
                    ),
                  if (viewModel.routeEnd != null)
                    Marker(
                      point: viewModel.routeEnd!,
                      width: 32,
                      height: 40,
                      alignment: Alignment.bottomCenter,
                      child: const MapPin(color: Colors.red),
                    ),
                ],
              ),
            ],
          ),

          // Shown while updateMapRoute() is fetching a new route (initial
          // load, switching subscriptions, or picking a different trip),
          // so the user gets feedback instead of a blank gap where the
          // line used to be.
          if (viewModel.isRouteLoading)
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primaryYellow),
                  ),
                ),
              ),
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