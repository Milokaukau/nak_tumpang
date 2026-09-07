import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';
import 'package:nak_tumpang/core/services/ors_service.dart';
import 'package:nak_tumpang/features/home/data/services/home_supabase_service.dart';
import 'package:nak_tumpang/core/services/gtfs_service.dart';
import 'package:nak_tumpang/core/utils/transit_utils.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class HomeViewModel extends ChangeNotifier {
  String selectedFilter = 'Direct';
  String currentUserRole = 'passenger';
  String? selectedSubscriptionId;

  Map<String, dynamic>? currentUser;
  Map<String, dynamic>? currentSelectedTrip;

  List<Map<String, dynamic>> availableTrips = [];
  List<Map<String, dynamic>> activeSubscriptions = [];

  bool isScreenLoading = true;
  bool isDirectLoading = false;
  bool isMixedLoading = false;
  bool isRouteLoading = false;
  bool showMatchingUI = false;
  bool _hasFoundDirect = false;
  bool _hasFoundMixed = false;

  int _fetchId = 0;
  int _routeFetchId = 0;
  int _userFetchId = 0;

  final ORSService _orsService = ORSService();
  final HomeSupabaseService _homeService = HomeSupabaseService();
  final GoTrueClient _auth = Supabase.instance.client.auth;

  List<Map<String, dynamic>> matchedDrivers = [];
  List<Map<String, dynamic>> mixedMatchedRoutes = [];

  List<({List<LatLng> points, Color color})> mapRoutes = [];
  List<({LatLng point, Color color})> mapMarkers = [];

  final Map<String, List<LatLng>> _routeCache = {};

  Future<List<LatLng>> _getCachedRoute(LatLng start, LatLng end) async {
    final cacheKey = '${start.latitude},${start.longitude}-${end.latitude},${end.longitude}';

    if (_routeCache.containsKey(cacheKey)) {
      return _routeCache[cacheKey]!;
    }

    final route = await _orsService.getRoute(start, end);
    _routeCache[cacheKey] = route;
    return route;
  }

  void toggleMatchingUI(bool show) {
    showMatchingUI = show;
    notifyListeners();
    updateMapRoute();
    if (show) {
      _matchCurrentRouteType();
    }
  }

  void setFilter(String option) {
    if (selectedFilter == option) return;
    selectedFilter = option;
    notifyListeners();

    if (showMatchingUI) {
      _matchCurrentRouteType();
    }
  }

  // ==========================================
  // FETCH METHODS
  // ==========================================

  Future<void> fetchCurrentUser() async {
    final requestId = ++_userFetchId;
    isScreenLoading = true;

    // --- FIX: Cleared Cache to prevent Memory Leaks across accounts ---
    _routeCache.clear();

    currentUserRole = 'passenger';
    currentUser = null;
    currentSelectedTrip = null;
    availableTrips = [];
    activeSubscriptions = [];
    selectedSubscriptionId = null;
    showMatchingUI = false;
    _hasFoundDirect = false;
    _hasFoundMixed = false;
    matchedDrivers = [];
    mixedMatchedRoutes = [];
    mapRoutes = [];
    mapMarkers = [];
    isRouteLoading = false;
    notifyListeners();

    final authUser = _auth.currentUser;
    if (authUser == null) {
      print('⚠️ fetchCurrentUser called with no authenticated user.');
      if (requestId == _userFetchId) {
        isScreenLoading = false;
        notifyListeners();
      }
      return;
    }

    // Fetch user profile and role directly from users table
    final profile = await _homeService.fetchUserProfile(authUser.id);
    if (requestId != _userFetchId) return;

    if (profile == null) {
      print('⚠️ fetchCurrentUser: user profile not found for ${authUser.id}');
      if (requestId == _userFetchId) {
        isScreenLoading = false;
        notifyListeners();
      }
      return;
    }

    currentUser = profile;
    final role = profile['role'] as String?;

    if (role == null || (role != 'driver' && role != 'passenger')) {
      print('⚠️ fetchCurrentUser: user ${authUser.id} has no valid role ($role).');
      if (requestId == _userFetchId) {
        isScreenLoading = false;
        notifyListeners();
      }
      return;
    }
    currentUserRole = role;

    if (role == 'driver') {
      await _loadDriverData(authUser.id, requestId);
    } else {
      await _loadPassengerData(authUser.id, requestId);
    }

    if (requestId == _userFetchId) {
      isScreenLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadDriverData(String userId, int requestId) async {
    try {
      final rawSubs = await _homeService.fetchDriverActiveSubscriptions(userId);
      if (requestId != _userFetchId) return;
      activeSubscriptions = _mapSubscriptions(rawSubs, isForPassenger: false);

      final allDriverTrips = await _homeService.fetchDriverTrips();
      if (requestId != _userFetchId) return;
      final myTrips = allDriverTrips.where((t) => t['user_id'] == userId).toList();

      final subbedTripIds = activeSubscriptions.map((s) => s['driver_trip_id']).toSet();
      availableTrips = myTrips.where((t) => !subbedTripIds.contains(t['id'])).toList();

      if (availableTrips.isNotEmpty) {
        currentSelectedTrip = availableTrips.first;
      }

      if (activeSubscriptions.isNotEmpty) {
        selectedSubscriptionId = activeSubscriptions.first['id'];
      }

      showMatchingUI = activeSubscriptions.isEmpty;
      updateMapRoute();
    } catch (e) {
      print('⚠️ Error fetching driver data: $e');
    }
  }

  Future<void> _loadPassengerData(String userId, int requestId) async {
    try {
      final trips = await _homeService.fetchPassengerTrips(userId);
      if (requestId != _userFetchId) return;
      final rawSubs = await _homeService.fetchAllPassengerSubscriptions(userId);
      if (requestId != _userFetchId) return;

      activeSubscriptions = _mapSubscriptions(rawSubs, isForPassenger: true);

      final subbedTripIds = activeSubscriptions.map((s) => s['passenger_trip_id']).toSet();
      availableTrips = trips.where((t) => !subbedTripIds.contains(t['id'])).toList();

      if (availableTrips.isNotEmpty) {
        currentSelectedTrip = availableTrips.first;
      }

      if (activeSubscriptions.isNotEmpty) {
        selectedSubscriptionId = activeSubscriptions.first['id'];
      }

      showMatchingUI = activeSubscriptions.isEmpty;
      updateMapRoute();

      if (showMatchingUI && currentSelectedTrip != null) {
        await _matchCurrentRouteType();
      }
    } catch (e) {
      print('⚠️ Error fetching initial data: $e');
    }
  }

  Future<void> changeTrip(String tripId) async {
    try {
      final selected = availableTrips.firstWhere((t) => t['id'] == tripId);
      currentSelectedTrip = selected;

      _hasFoundDirect = false;
      _hasFoundMixed = false;
      matchedDrivers.clear();
      mixedMatchedRoutes.clear();

      updateMapRoute();

      if (showMatchingUI) {
        await _matchCurrentRouteType();
      }
    } catch (e) {
      print('⚠️ Error changing trip: $e');
    }
  }

  // ==========================================
  // MATCHING LOGIC
  // ==========================================

  Future<void> _matchCurrentRouteType() async {
    if (selectedFilter == 'Direct' && !_hasFoundDirect) {
      await _findDirectDrivers();
    } else if (selectedFilter == 'Mixed' && !_hasFoundMixed) {
      await _findMixedRoutes();
    }
  }

  Future<void> _findDirectDrivers() async {
    if (currentSelectedTrip == null) return;

    final currentFetchId = ++_fetchId;
    isDirectLoading = true;
    notifyListeners();

    final passDays = _extractActiveDays(currentSelectedTrip!);
    final passPick = _latLngFromMap(currentSelectedTrip!, 'pickup_lat', 'pickup_lng');
    final passDrop = _latLngFromMap(currentSelectedTrip!, 'dropoff_lat', 'dropoff_lng');
    final passTime = _sqlTimeToMinutes(currentSelectedTrip!['desired_pickup_time']);

    final driverTrips = await _homeService.fetchDriverTrips();
    if (_fetchId != currentFetchId) return;

    List<Map<String, dynamic>> tempMatchedDrivers = [];

    for (var driverTrip in driverTrips) {
      if (_fetchId != currentFetchId) return;

      final driverName = driverTrip['users']?['name'] ?? 'Unknown Driver';
      final driverDays = _extractActiveDays(driverTrip);

      if (!MatchingUtils.hasOverlappingDays(passDays, driverDays)) continue;

      final drivTime = _sqlTimeToMinutes(driverTrip['depart_time']);
      if ((drivTime - passTime).abs() > 30) continue;

      final drivStart = _latLngFromMap(driverTrip, 'depart_lat', 'depart_lng');
      final drivEnd = _latLngFromMap(driverTrip, 'arrival_lat', 'arrival_lng');

      if (drivStart.latitude == 0 || drivEnd.latitude == 0) continue;

      final pickDist = MatchingUtils.calculateDistance(
        passPick.latitude, passPick.longitude, drivStart.latitude, drivStart.longitude,
      );
      final dropDist = MatchingUtils.calculateDistance(
        passDrop.latitude, passDrop.longitude, drivEnd.latitude, drivEnd.longitude,
      );

      if (pickDist > 15000 || dropDist > 15000) continue;

      try {
        final driverRoute = await _getCachedRoute(drivStart, drivEnd);
        if (_fetchId != currentFetchId) return;

        if (MatchingUtils.isRouteMatch(passPick, passDrop, driverRoute, 800)) {
          tempMatchedDrivers.add({
            'id': driverTrip['user_id'],
            'name': driverName,
            'phone': driverTrip['users']?['phone'] ?? 'N/A',
            'profile_image_url': driverTrip['users']?['avatar_url'],
            'pickup_distance_km': pickDist / 1000,
            'driver_profile': {
              'depart_time': _formatSqlTimeToUI(driverTrip['depart_time']),
            },
          });
        }
      } catch (e) {
        print('⚠️ ORS Route Error: $e');
        if (e.toString().contains('Quota') || e.toString().contains('SocketException')) {
          break;
        }
        continue;
      }
    }

    if (_fetchId != currentFetchId) return;

    matchedDrivers = tempMatchedDrivers;
    _hasFoundDirect = true;
    isDirectLoading = false;
    notifyListeners();
  }

  Future<void> _findMixedRoutes() async {
    if (currentSelectedTrip == null) return;

    final currentFetchId = ++_fetchId;
    isMixedLoading = true;
    notifyListeners();

    final passDays = _extractActiveDays(currentSelectedTrip!);
    final passPick = _latLngFromMap(currentSelectedTrip!, 'pickup_lat', 'pickup_lng');
    final passDrop = _latLngFromMap(currentSelectedTrip!, 'dropoff_lat', 'dropoff_lng');
    final passTime = _sqlTimeToMinutes(currentSelectedTrip!['desired_pickup_time']);

    final driverTrips = await _homeService.fetchDriverTrips();
    if (_fetchId != currentFetchId) return;

    await GtfsService().initStations();
    if (_fetchId != currentFetchId) return;

    List<Map<String, dynamic>> tempMixedRoutes = [];

    try {
      final pickStation = TransitUtils.findNearestStation(passPick);
      final dropStation = TransitUtils.findNearestStation(passDrop);

      if (pickStation == null || dropStation == null) {
        _hasFoundMixed = true;
        isMixedLoading = false;
        notifyListeners();
        return;
      }

      final isInterchange = pickStation.lineId != dropStation.lineId;
      int trainDuration;

      if (isInterchange) {
        final transitDist = MatchingUtils.calculateDistance(
          pickStation.location.latitude, pickStation.location.longitude,
          dropStation.location.latitude, dropStation.location.longitude,
        );
        trainDuration = (transitDist / 660).ceil() + 10;
      } else {
        trainDuration = TransitUtils.calculateTrainDuration(pickStation, dropStation);
      }

      final pickWalkMetrics = await _orsService.getWalkingMetrics(passPick, pickStation.location);
      if (_fetchId != currentFetchId) return;

      final dropWalkMetrics = await _orsService.getWalkingMetrics(dropStation.location, passDrop);
      if (_fetchId != currentFetchId) return;

      final walkDistToStation = pickWalkMetrics['distance'];
      final walkDurationToStation = (pickWalkMetrics['duration'] / 60).ceil();

      final walkDistToDest = dropWalkMetrics['distance'];
      final walkDurationToDest = (dropWalkMetrics['duration'] / 60).ceil();

      final firstMileOptions = <Map<String, dynamic>>[];
      final lastMileOptions = <Map<String, dynamic>>[];

      if (walkDistToStation <= 1500) {
        firstMileOptions.add({
          'type': 'Walk',
          'arrival_at_board_station': passTime + walkDurationToStation,
        });
      }
      if (walkDistToDest <= 1500) {
        lastMileOptions.add({'type': 'Walk'});
      }

      for (var driverTrip in driverTrips) {
        if (_fetchId != currentFetchId) return;

        final driverDays = _extractActiveDays(driverTrip);
        if (!MatchingUtils.hasOverlappingDays(passDays, driverDays)) continue;

        final drivStart = LatLng(_parseDouble(driverTrip['depart_lat']), _parseDouble(driverTrip['depart_lng']));
        final drivEnd = LatLng(_parseDouble(driverTrip['arrival_lat']), _parseDouble(driverTrip['arrival_lng']));
        final drivTime = _sqlTimeToMinutes(driverTrip['depart_time']);
        final driverName = driverTrip['users']?['name'] ?? 'Unknown Driver';

        if (drivStart.latitude == 0 || drivEnd.latitude == 0) continue;

        try {
          if ((drivTime - passTime).abs() <= 30) {
            final pickDist = MatchingUtils.calculateDistance(
              passPick.latitude, passPick.longitude, drivStart.latitude, drivStart.longitude,
            );
            final dropDistToStation = MatchingUtils.calculateDistance(
              pickStation.location.latitude, pickStation.location.longitude, drivEnd.latitude, drivEnd.longitude,
            );

            if (pickDist <= 15000 && dropDistToStation <= 15000) {
              final driverRoute = await _getCachedRoute(drivStart, drivEnd);
              if (_fetchId != currentFetchId) return;

              if (MatchingUtils.isRouteMatch(passPick, pickStation.location, driverRoute, 800)) {
                final routeDistToStation = MatchingUtils.calculateDistance(
                  passPick.latitude, passPick.longitude, pickStation.location.latitude, pickStation.location.longitude,
                );
                final driveMinsToStation = (routeDistToStation / 400).ceil();

                firstMileOptions.add({
                  'type': 'Driver',
                  'driver_name': driverName,
                  'depart_time': _formatSqlTimeToUI(driverTrip['depart_time']),
                  'distance_km': pickDist / 1000,
                  'arrival_at_board_station': drivTime + driveMinsToStation,
                });
              }
            }
          }

          if (drivTime > passTime) {
            final pickDistFromStation = MatchingUtils.calculateDistance(
              dropStation.location.latitude, dropStation.location.longitude, drivStart.latitude, drivStart.longitude,
            );
            final dropDistToDest = MatchingUtils.calculateDistance(
              passDrop.latitude, passDrop.longitude, drivEnd.latitude, drivEnd.longitude,
            );

            if (pickDistFromStation <= 15000 && dropDistToDest <= 15000) {
              final driverRoute = await _getCachedRoute(drivStart, drivEnd);
              if (_fetchId != currentFetchId) return;

              if (MatchingUtils.isRouteMatch(dropStation.location, passDrop, driverRoute, 800)) {
                lastMileOptions.add({
                  'type': 'Driver',
                  'driver_name': driverName,
                  'depart_time': _formatSqlTimeToUI(driverTrip['depart_time']),
                  'depart_time_mins': drivTime,
                  'distance_km': pickDistFromStation / 1000,
                });
              }
            }
          }
        } catch (e) {
          print('⚠️ ORS Route Error inside mixed loop: $e');
          if (e.toString().contains('Quota') || e.toString().contains('SocketException')) {
            break;
          }
          continue;
        }
      }

      for (var fm in firstMileOptions) {
        final arrivalAtDropStation = fm['arrival_at_board_station'] + trainDuration;

        for (var lm in lastMileOptions) {
          if (fm['type'] == 'Driver' && lm['type'] == 'Driver' && fm['driver_name'] == lm['driver_name']) {
            continue;
          }

          if (lm['type'] == 'Driver') {
            final lmDepart = lm['depart_time_mins'];
            if ((lmDepart - arrivalAtDropStation).abs() > 45) continue;
          }

          tempMixedRoutes.add({
            'first_mile_type': fm['type'],
            'driver_a_name': fm['driver_name'],
            'driver_a_depart': fm['depart_time'],
            'pickup_distance_km': fm['distance_km'],
            'walk_to_station_meters': walkDistToStation,
            'walk_to_station_mins': walkDurationToStation,

            'board_station': pickStation.name,
            'alight_station': dropStation.name,

            'is_interchange': isInterchange,
            'board_line_name': pickStation.lineName,
            'board_line_short_name': pickStation.lineShortName,
            'board_line_color': pickStation.lineColor,
            'alight_line_name': dropStation.lineName,
            'alight_line_short_name': dropStation.lineShortName,
            'alight_line_color': dropStation.lineColor,
            'train_duration_mins': trainDuration,

            'last_mile_type': lm['type'],
            'driver_b_name': lm['driver_name'],
            'driver_b_depart': lm['depart_time'],
            'dropoff_distance_km': lm['distance_km'],
            'walk_to_dest_meters': walkDistToDest,
            'walk_to_dest_mins': walkDurationToDest,

            'pickup_name': currentSelectedTrip?['pickup_name'] ?? 'Pickup',
            'destination_name': currentSelectedTrip?['dropoff_name'] ?? 'Destination',
          });
        }
      }
    } catch (e) {
      print('Error generating mixed routes: $e');
    }

    if (_fetchId != currentFetchId) return;

    mixedMatchedRoutes = tempMixedRoutes;
    _hasFoundMixed = true;
    isMixedLoading = false;
    notifyListeners();
  }

  // ==========================================
  // MAP ROUTE LOGIC
  // ==========================================

  void selectSubscription(String subId) {
    if (selectedSubscriptionId == subId) return;
    selectedSubscriptionId = subId;
    notifyListeners();
    updateMapRoute();
  }

  void _clearMap() {
    _routeFetchId++;
    mapRoutes = [];
    mapMarkers = [];
    isRouteLoading = false;
    notifyListeners();
  }

  Future<void> updateMapRoute() async {
    final requestId = ++_routeFetchId;
    mapRoutes = [];
    mapMarkers = [];
    isRouteLoading = true;
    notifyListeners();

    try {
      if (currentUserRole == 'passenger') {
        LatLng? start, end;

        if (showMatchingUI) {
          if (currentSelectedTrip == null) return _clearMap();
          start = _latLngFromMap(currentSelectedTrip!, 'pickup_lat', 'pickup_lng');
          end = _latLngFromMap(currentSelectedTrip!, 'dropoff_lat', 'dropoff_lng');
        } else {
          if (selectedSubscriptionId == null || activeSubscriptions.isEmpty) return _clearMap();
          final sub = activeSubscriptions.firstWhere((s) => s['id'] == selectedSubscriptionId, orElse: () => <String, dynamic>{});
          if (sub.isEmpty) return _clearMap();

          start = _latLngFromMap(sub, 'pickup_lat', 'pickup_lng');
          end = _latLngFromMap(sub, 'dropoff_lat', 'dropoff_lng');
        }

        // --- FIX: Idiomatic Safe Check ---
        if (start?.latitude == 0.0 || end?.latitude == 0.0) return _clearMap();

        final route = await _getCachedRoute(start!, end!);
        if (requestId != _routeFetchId) return;

        mapRoutes = [
          (points: [start, ...route, end], color: Colors.blueAccent),
        ];
        mapMarkers = [
          (point: start, color: Colors.green),
          (point: end, color: Colors.red),
        ];
      }
      else if (currentUserRole == 'driver') {
        if (showMatchingUI) {
          if (currentSelectedTrip == null) return _clearMap();
          final depart = _latLngFromMap(currentSelectedTrip!, 'depart_lat', 'depart_lng');
          final arrival = _latLngFromMap(currentSelectedTrip!, 'arrival_lat', 'arrival_lng');

          if (depart.latitude == 0.0 || arrival.latitude == 0.0) return _clearMap();

          final route = await _getCachedRoute(depart, arrival);
          if (requestId != _routeFetchId) return;

          mapRoutes = [
            (points: [depart, ...route, arrival], color: Colors.blueAccent),
          ];
          mapMarkers = [
            (point: depart, color: Colors.black),
            (point: arrival, color: Colors.black),
          ];
        } else {
          if (selectedSubscriptionId == null || activeSubscriptions.isEmpty) return _clearMap();
          final sub = activeSubscriptions.firstWhere((s) => s['id'] == selectedSubscriptionId, orElse: () => <String, dynamic>{});
          if (sub.isEmpty) return _clearMap();

          final depart = _latLngFromMap(sub, 'driver_depart_lat', 'driver_depart_lng');
          final pickup = _latLngFromMap(sub, 'pickup_lat', 'pickup_lng');
          final dropoff = _latLngFromMap(sub, 'dropoff_lat', 'dropoff_lng');
          final arrival = _latLngFromMap(sub, 'driver_arrival_lat', 'driver_arrival_lng');

          final validDepart = depart.latitude != 0.0 && depart.longitude != 0.0;
          final validArrival = arrival.latitude != 0.0 && arrival.longitude != 0.0;

          final segments = await Future.wait([
            validDepart ? _getCachedRoute(depart, pickup) : Future.value(<LatLng>[]),
            _getCachedRoute(pickup, dropoff),
            validArrival ? _getCachedRoute(dropoff, arrival) : Future.value(<LatLng>[]),
          ]);
          if (requestId != _routeFetchId) return;

          mapRoutes = [
            if (validDepart) (points: [depart, ...segments[0], pickup], color: AppColors.primaryYellow),
            (points: [pickup, ...segments[1], dropoff], color: Colors.blueAccent),
            if (validArrival) (points: [dropoff, ...segments[2], arrival], color: AppColors.primaryYellow),
          ];

          mapMarkers = [
            if (validDepart) (point: depart, color: Colors.black),
            (point: pickup, color: Colors.green),
            (point: dropoff, color: Colors.red),
            if (validArrival) (point: arrival, color: Colors.black),
          ];
        }
      }
    } catch (e) {
      print('⚠️ Error updating map route: $e');
    } finally {
      if (requestId == _routeFetchId) {
        isRouteLoading = false;
        notifyListeners();
      }
    }
  }

  // ==========================================
  // HELPERS
  // ==========================================

  List<Map<String, dynamic>> _mapSubscriptions(
      List<Map<String, dynamic>> rawSubs, {
        required bool isForPassenger,
      }) {
    return rawSubs.map((sub) {
      final tripKey = isForPassenger ? 'driver_trips' : 'passenger_trips';
      final defaultName = isForPassenger ? 'Unknown Driver' : 'Unknown Passenger';

      final trip = sub[tripKey] ?? {};
      final user = trip['users'] ?? {};
      final driverTrip = isForPassenger ? trip : (sub['driver_trips'] ?? {});

      return {
        'id': sub['id'],
        'passenger_trip_id': sub['passenger_trip_id'],
        'driver_trip_id': sub['driver_trip_id'],
        'pickup_lat': sub['pickup_lat'],
        'pickup_lng': sub['pickup_lng'],
        'dropoff_lat': sub['dropoff_lat'],
        'dropoff_lng': sub['dropoff_lng'],

        'driver_depart_lat': driverTrip['depart_lat'],
        'driver_depart_lng': driverTrip['depart_lng'],
        'driver_arrival_lat': driverTrip['arrival_lat'],
        'driver_arrival_lng': driverTrip['arrival_lng'],

        'name': user['name'] ?? defaultName,
        'phone': user['phone'] ?? 'N/A',
        'imageUrl': user['avatar_url'],
        'pickup_location': sub['pickup_location'] ?? 'Unknown',
        'dropoff_location': sub['dropoff_location'] ?? 'Unknown',
        'pickup_time': sub['pickup_time'] != null
            ? _formatSqlTimeToUI(sub['pickup_time'])
            : 'TBD',
      };
    }).toList();
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  LatLng _latLngFromMap(
      Map<String, dynamic> map,
      String latKey,
      String lngKey,
      ) {
    return LatLng(_parseDouble(map[latKey]), _parseDouble(map[lngKey]));
  }

  int _sqlTimeToMinutes(String sqlTime) {
    final parts = sqlTime.split(':');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    return (hours * 60) + minutes;
  }

  String _formatSqlTimeToUI(String sqlTime) {
    final parts = sqlTime.split(':');
    int hours = int.parse(parts[0]);
    final minutes = parts[1];

    final period = hours >= 12 ? 'PM' : 'AM';
    if (hours > 12) hours -= 12;
    if (hours == 0) hours = 12;

    final hoursStr = hours.toString().padLeft(2, '0');
    return '$hoursStr:$minutes $period';
  }

  Map<String, bool> _extractActiveDays(Map<String, dynamic> row) {
    return {
      'monday': row['active_monday'] ?? false,
      'tuesday': row['active_tuesday'] ?? false,
      'wednesday': row['active_wednesday'] ?? false,
      'thursday': row['active_thursday'] ?? false,
      'friday': row['active_friday'] ?? false,
      'saturday': row['active_saturday'] ?? false,
      'sunday': row['active_sunday'] ?? false,
    };
  }
}