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

  // Content signature of the last-fitted points, not the list's identity
  // hashCode. mapRoutes is reassigned to a brand-new list on every
  // updateMapRoute() call, even when the route content is unchanged
  // (e.g. toggling matching-UI on/off for the same trip) — a hashCode
  // check would treat that as "changed" and yank the camera back to a
  // fit view, overriding a pan/zoom the user just did.
  String? _lastRouteSignature;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().fetchCurrentUser();
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _maybeUpdateCamera(List<LatLng> points) {
    if (points.isEmpty) return;

    final signature = points.map((p) => '${p.latitude},${p.longitude}').join('|');
    if (signature == _lastRouteSignature) return;
    _lastRouteSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The screen (and this controller) may have been disposed between
      // scheduling this callback and it firing (e.g. the user logged out
      // right after a fetch resolved).
      if (!mounted) return;

      final bounds = LatLngBounds.fromPoints(points);
      final isDegenerate = bounds.north == bounds.south && bounds.east == bounds.west;

      if (!isDegenerate) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(40.0),
          ),
        );
      } else {
        // A single point, or duplicate start/end coordinates, has no
        // meaningful area to fit -- just center on it instead, since
        // fitCamera on zero-area bounds produces an unpredictable zoom.
        _mapController.move(points.first, 15.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();
    final userName = viewModel.currentUser?['name'] ?? 'User';

    final allPoints = viewModel.mapRoutes.expand((r) => r.points).toList();
    _maybeUpdateCamera(allPoints);

    final initialCenter = allPoints.firstOrNull ?? const LatLng(3.1578, 101.7118);

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
              PolylineLayer(
                polylines: viewModel.mapRoutes.map((routeData) {
                  return Polyline(
                    points: routeData.points,
                    strokeWidth: 5.0,
                    color: routeData.color,
                  );
                }).toList(),
              ),
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