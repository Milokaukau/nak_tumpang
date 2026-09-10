import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
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
  String? _lastRouteSignature;

  // Added state for user location
  LatLng? _userLocation;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().fetchCurrentUser();
      _fetchUserLocation(centerMap: false); // Fetch quietly on load
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // Added function to get GPS and optionally center the camera
  Future<void> _fetchUserLocation({required bool centerMap}) async {
    setState(() => _isLocating = true);

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (centerMap && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission needed.')),
          );
        }
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        if (centerMap && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please turn on location services.')),
          );
        }
        return;
      }

      // 1. Instant fallback to last known location
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        final lastLatLng = LatLng(lastKnown.latitude, lastKnown.longitude);
        setState(() => _userLocation = lastLatLng);

        // --- FIX: Center camera if asked OR if there is no active route ---
        final hasRoute = context.read<HomeViewModel>().mapRoutes.isNotEmpty;
        if (centerMap || !hasRoute) {
          _mapController.move(lastLatLng, 15.0);
        }
      }

      // 2. Fetch fresh position with a 5-second limit
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      if (!mounted) return;

      final currentLatLng = LatLng(position.latitude, position.longitude);
      setState(() => _userLocation = currentLatLng);

      // --- FIX: Center camera if asked OR if there is no active route ---
      final hasRoute = context.read<HomeViewModel>().mapRoutes.isNotEmpty;
      if (centerMap || !hasRoute) {
        _mapController.move(currentLatLng, 15.0);
      }

    } catch (e) {
      debugPrint('Location fetch notice: $e');
      // --- FIX: Show SnackBar if the user tapped the button and it timed out/failed ---
      if (centerMap && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Could not get your location. Please try again.')),
          );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _maybeUpdateCamera(List<LatLng> points) {
    if (points.isEmpty) return;

    final signature = points.map((p) => '${p.latitude},${p.longitude}').join('|');
    if (signature == _lastRouteSignature) return;
    _lastRouteSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
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

    final initialCenter = allPoints.firstOrNull ?? _userLocation ?? const LatLng(3.1578, 101.7118);

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
                    strokeJoin: StrokeJoin.round,
                    strokeCap: StrokeCap.round,
                  );
                }).toList(),
              ),
              MarkerLayer(
                markers: [
                  ...viewModel.mapMarkers.map((markerData) {
                    return Marker(
                      point: markerData.point,
                      width: 32,
                      height: 40,
                      alignment: Alignment.bottomCenter,
                      child: MapPin(color: markerData.color),
                    );
                  }),
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!,
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                ],
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

          Positioned(
            top: 110,
            right: 16,
            child: Material(
              color: AppColors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _isLocating ? null : () => _fetchUserLocation(centerMap: true),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _isLocating
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryYellow),
                  )
                      : const Icon(Icons.my_location, color: AppColors.black, size: 20),
                ),
              ),
            ),
          ),

          const HomePanel(),
        ],
      ),
    );
  }
}