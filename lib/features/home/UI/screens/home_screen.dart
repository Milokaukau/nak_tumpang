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

  // Lightweight signature of the currently drawn points. We only re-fit the
  // camera when the actual route/markers change, not on every rebuild
  // (unlike the previous List.hashCode approach, this is stable across
  // rebuilds that produce an equal-but-not-identical list).
  String? _lastRouteSignature;

  static const LatLng _defaultCenter = LatLng(3.1578, 101.7118);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // TODO(remove-before-release): seeds a mock driver for manual testing
      // of the driver view. Replace with the real auth/user bootstrap flow
      // before this ships -- flag if this is still needed for the demo.
      context.read<HomeViewModel>().fetchMockPassenger();
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<LatLng> _collectVisiblePoints(HomeViewModel viewModel) {
    return [
      for (final route in viewModel.mapRoutes) ...route.points,
      for (final marker in viewModel.mapMarkers) marker.point,
    ];
  }

  void _maybeUpdateCamera(List<LatLng> points) {
    if (points.isEmpty) return;

    final signature = points.map((p) => '${p.latitude},${p.longitude}').join('|');
    if (signature == _lastRouteSignature) return;
    _lastRouteSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length > 1) {
        // Fit the whole route (e.g. departure -> pickup -> dropoff ->
        // destination) instead of only centering on the first point, so a
        // 30km trip doesn't require the user to manually zoom out.
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(48.0),
          ),
        );
      } else {
        // A single point has no meaningful bounds to fit -- just center on
        // it, otherwise fitCamera's degenerate zero-area bounds produce an
        // unpredictable zoom level.
        _mapController.move(points.first, 15.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();
    final userName = viewModel.currentUser?['name'] ?? 'Loading...';

    final visiblePoints = _collectVisiblePoints(viewModel);
    _maybeUpdateCamera(visiblePoints);

    final initialCenter = visiblePoints.isNotEmpty ? visiblePoints.first : _defaultCenter;

    return Scaffold(
      endDrawer: AppSidebar(
        userName: userName,
        userRole: viewModel.currentUserRole == 'driver' ? 'Driver' : 'Passenger',
        selectedIndex: -1,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 15.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.naktumpang.app',
              ),

              // --- 1. DYNAMIC POLYLINES ---
              PolylineLayer(
                polylines: viewModel.mapRoutes.map((routeData) {
                  return Polyline(
                    points: routeData.points,
                    strokeWidth: 5.0,
                    color: routeData.color,
                  );
                }).toList(),
              ),

              // --- 2. DYNAMIC MARKERS ---
              MarkerLayer(
                markers: viewModel.mapMarkers.map((markerData) {
                  return Marker(
                    point: markerData.point,
                    width: 32,
                    height: 40,
                    alignment: Alignment.bottomCenter,
                    child: MapPin(color: markerData.color),
                  );
                }).toList(),
              ),
            ],
          ),

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