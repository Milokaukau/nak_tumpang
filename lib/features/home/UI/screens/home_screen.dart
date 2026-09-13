import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nak_tumpang/core/components/map_pin.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/components/app_sidebar.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/home/UI/components/home_panel.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:nak_tumpang/features/subscriptions/data/services/subscription_supabase_service.dart';
import 'package:nak_tumpang/features/subscriptions/UI/screens/subscription_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();
  final SubscriptionSupabaseService _subscriptionService = SubscriptionSupabaseService();

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
      _initializeNotifications();
    });
  }

  Future<void> _initializeNotifications() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await _checkCrossSideNotifications(userId);
    }
  }

  Future<void> _checkCrossSideNotifications(String userId) async {
    final notifications = await _subscriptionService.fetchUnreadNotifications(userId);

    if (notifications.isEmpty || !mounted) return;

    List<String> idsToMarkRead = [];
    final viewModel = context.read<HomeViewModel>();
    final userRole = viewModel.currentUserRole == 'driver' ? 'driver' : 'passenger';

    for (var notif in notifications) {
      idsToMarkRead.add(notif['id']);

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) break;

      _showTopNotification(notif, userRole);
    }

    if (idsToMarkRead.isNotEmpty) {
      await _subscriptionService.markNotificationsAsRead(idsToMarkRead);
    }
  }

  void _showTopNotification(Map<String, dynamic> notif, String role) {
    final title = notif['title'] ?? 'Notification';
    final message = notif['message'] ?? '';
    final subscriptionId = notif['subscription_id'];

    final overlay = Overlay.of(context);
    OverlayEntry? entry;

    entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: MediaQuery.of(overlayContext).padding.top + 16,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () async {
              entry?.remove();

              if (subscriptionId == null || subscriptionId.toString().isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error: No subscription ID attached to this notification in Supabase.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }

              if (!mounted) return;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryYellow),
                ),
              );

              final subscriptionData = await context.read<HomeViewModel>().fetchSubscriptionForNotification(
                subscriptionId.toString(),
                role,
              );

              if (!mounted) return;
              Navigator.pop(context); // close loading indicator

              if (subscriptionData == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to load subscription details.'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 4),
                  ),
                );
                return;
              }

              final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
              final initialTab = (notif['type'] == 'exception') ? 1 : 0;

              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SubscriptionDetailScreen(
                      subscription: subscriptionData,
                      currentUserId: currentUserId,
                      role: role,
                      initialTabIndex: initialTab,
                    ),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryYellow,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_active, color: Colors.black87, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(message, style: const TextStyle(color: Colors.black87, fontSize: 13)),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('Tap to view', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black54, fontSize: 12)),
                      Icon(Icons.chevron_right, size: 16, color: Colors.black54),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry!);

    Future.delayed(const Duration(seconds: 20), () {
      if (entry?.mounted ?? false) {
        entry?.remove();
      }
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
              if (!NetworkService.isOfflineNotifier.value)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.naktumpang.app',
                ),
              PolylineLayer(
                polylines: viewModel.mapRoutes.map((routeData) {
                  return Polyline(
                    points: routeData.points,
                    // Draw a slightly thinner line for the train transit leg
                    strokeWidth: routeData.isTransit ? 3.5 : 5.0,
                    color: routeData.color,
                    strokeJoin: StrokeJoin.round,
                    strokeCap: StrokeCap.round,
                  );
                }).toList(),
              ),
              // 2. Pins paint last (on top of the lines)
              MarkerLayer(
                markers: [
                  ...viewModel.mapMarkers.map((markerData) {
                    return Marker(
                      point: markerData.point,
                      // Shrink the bounding box if it's a small connection node
                      width: markerData.isSmallNode ? 16.0 : 32.0,
                      height: markerData.isSmallNode ? 16.0 : 40.0,
                      alignment: Alignment.center,
                      child: markerData.isSmallNode
                      // Draw the small connection circle [-o-] centered exactly on the coordinate
                          ? Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: markerData.color, width: 4.0),
                        ),
                      )
                      // Draw the standard large pin, pushed up so its tip hits the coordinate
                          : Transform.translate(
                        offset: const Offset(0, -20),
                        child: MapPin(color: markerData.color),
                      ),
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