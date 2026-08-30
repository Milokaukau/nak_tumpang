import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';
import 'package:nak_tumpang/core/services/ors_service.dart';
import 'package:nak_tumpang/features/home/data/services/home_supabase_service.dart';
import 'package:nak_tumpang/core/services/gtfs_service.dart';
import 'package:nak_tumpang/core/utils/transit_utils.dart';

class HomeViewModel extends ChangeNotifier {
  String selectedFilter = 'Direct';
  Map<String, dynamic>? currentPassenger;
  Map<String, dynamic>? currentPassengerTrip;

  List<Map<String, dynamic>> availableTrips = [];

  bool isScreenLoading = true;
  bool isDirectLoading = false;
  bool isMixedLoading = false;
  bool _hasFoundDirect = false;
  bool _hasFoundMixed = false;

  int _fetchId = 0;

  final ORSService _orsService = ORSService();
  final HomeSupabaseService _homeService = HomeSupabaseService();

  List<Map<String, dynamic>> matchedDrivers = [];
  List<Map<String, dynamic>> mixedMatchedRoutes = [];

  void setFilter(String option) {
    if (selectedFilter == option) return;
    selectedFilter = option;
    notifyListeners();
    _matchCurrentRouteType();
  }

  void changeTrip(String tripId) {
    if (isScreenLoading) return;

    final selected = availableTrips.firstWhere((t) => t['id'] == tripId);
    currentPassengerTrip = selected;

    _hasFoundDirect = false;
    _hasFoundMixed = false;
    matchedDrivers.clear();
    mixedMatchedRoutes.clear();

    _matchCurrentRouteType();
  }

  Future<void> fetchMockPassenger() async {
    isScreenLoading = true;
    notifyListeners();

    final trips = await _homeService.fetchPassengerTrips('usr_pass_9921');

    if (trips.isNotEmpty) {
      availableTrips = trips;
      currentPassengerTrip = trips.first;
      currentPassenger = trips.first['users'];

      _hasFoundDirect = false;
      _hasFoundMixed = false;
      matchedDrivers.clear();
      mixedMatchedRoutes.clear();

      await _matchCurrentRouteType();
    } else {
      print('❌ Failed to fetch passenger trips.');
    }

    isScreenLoading = false;
    notifyListeners();
  }

  Future<void> _matchCurrentRouteType() async {
    if (selectedFilter == 'Direct' && !_hasFoundDirect) {
      await _findDirectDrivers();
    } else if (selectedFilter == 'Mixed' && !_hasFoundMixed) {
      await _findMixedRoutes();
    }
  }

  Future<void> _findDirectDrivers() async {
    if (currentPassengerTrip == null) return;

    final currentFetchId = ++_fetchId;
    isDirectLoading = true;
    notifyListeners();

    final passDays = _extractActiveDays(currentPassengerTrip!);
    final passPick = LatLng(
        _parseDouble(currentPassengerTrip!['pickup_lat']),
        _parseDouble(currentPassengerTrip!['pickup_lng'])
    );
    final passDrop = LatLng(
        _parseDouble(currentPassengerTrip!['dropoff_lat']),
        _parseDouble(currentPassengerTrip!['dropoff_lng'])
    );
    final passTime = _sqlTimeToMinutes(currentPassengerTrip!['desired_pickup_time']);

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

      final drivStart = LatLng(
          _parseDouble(driverTrip['depart_lat']),
          _parseDouble(driverTrip['depart_lng'])
      );
      final drivEnd = LatLng(
          _parseDouble(driverTrip['arrival_lat'] ?? driverTrip['ariival_lat']),
          _parseDouble(driverTrip['arrival_lng'] ?? driverTrip['ariival_lng'])
      );

      if (drivStart.latitude == 0 || drivEnd.latitude == 0) continue;

      final pickDist = MatchingUtils.calculateDistance(
          passPick.latitude, passPick.longitude,
          drivStart.latitude, drivStart.longitude
      );
      final dropDist = MatchingUtils.calculateDistance(
          passDrop.latitude, passDrop.longitude,
          drivEnd.latitude, drivEnd.longitude
      );

      if (pickDist > 15000 || dropDist > 15000) continue;

      try {
        final driverRoute = await _orsService.getRoute(drivStart, drivEnd);
        if (_fetchId != currentFetchId) return;

        if (MatchingUtils.isRouteMatch(passPick, passDrop, driverRoute, 800)) {
          tempMatchedDrivers.add({
            'id': driverTrip['user_id'],
            'name': driverName,
            'phone': driverTrip['users']?['phone'] ?? 'N/A',
            'profile_image_url': driverTrip['users']?['profile_image_url'],
            'pickup_distance_km': pickDist / 1000,
            'driver_profile': {
              'depart_time': _formatSqlTimeToUI(driverTrip['depart_time']),
            }
          });
        }
      } catch (e) {
        print('⚠️ ORS Route Error: $e');
        continue;
      }
    }

    if (_fetchId != currentFetchId) return;

    if (tempMatchedDrivers.isEmpty) {
      tempMatchedDrivers = _getHardcodedDirectData();
    }

    matchedDrivers = tempMatchedDrivers;
    _hasFoundDirect = true;
    isDirectLoading = false;
    notifyListeners();
  }

  Future<void> _findMixedRoutes() async {
    if (currentPassengerTrip == null) return;

    final currentFetchId = ++_fetchId;
    isMixedLoading = true;
    notifyListeners();

    final passDays = _extractActiveDays(currentPassengerTrip!);
    final passPick = LatLng(
        _parseDouble(currentPassengerTrip!['pickup_lat']),
        _parseDouble(currentPassengerTrip!['pickup_lng'])
    );
    final passDrop = LatLng(
        _parseDouble(currentPassengerTrip!['dropoff_lat']),
        _parseDouble(currentPassengerTrip!['dropoff_lng'])
    );
    final passTime = _sqlTimeToMinutes(currentPassengerTrip!['desired_pickup_time']);

    final driverTrips = await _homeService.fetchDriverTrips();
    if (_fetchId != currentFetchId) return;

    await GtfsService().initStations();
    if (_fetchId != currentFetchId) return;

    List<Map<String, dynamic>> tempMixedRoutes = [];

    try {
      final pickStation = TransitUtils.findNearestStation(passPick);
      final dropStation = TransitUtils.findNearestStation(passDrop);

      if (pickStation == null || dropStation == null) {
        // --- NEW: Inject fallback on early exit ---
        mixedMatchedRoutes = _getHardcodedMixedData();
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
            dropStation.location.latitude, dropStation.location.longitude
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
        final drivEnd = LatLng(
            _parseDouble(driverTrip['arrival_lat'] ?? driverTrip['ariival_lat']),
            _parseDouble(driverTrip['arrival_lng'] ?? driverTrip['ariival_lng'])
        );
        final drivTime = _sqlTimeToMinutes(driverTrip['depart_time']);
        final driverName = driverTrip['users']?['name'] ?? 'Unknown Driver';

        if (drivStart.latitude == 0 || drivEnd.latitude == 0) continue;

        if ((drivTime - passTime).abs() <= 30) {
          final pickDist = MatchingUtils.calculateDistance(passPick.latitude, passPick.longitude, drivStart.latitude, drivStart.longitude);
          final dropDistToStation = MatchingUtils.calculateDistance(pickStation.location.latitude, pickStation.location.longitude, drivEnd.latitude, drivEnd.longitude);

          if (pickDist <= 15000 && dropDistToStation <= 15000) {
            final driverRoute = await _orsService.getRoute(drivStart, drivEnd);
            if (_fetchId != currentFetchId) return;

            if (MatchingUtils.isRouteMatch(passPick, pickStation.location, driverRoute, 800)) {
              final routeDistToStation = MatchingUtils.calculateDistance(passPick.latitude, passPick.longitude, pickStation.location.latitude, pickStation.location.longitude);
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
          final pickDistFromStation = MatchingUtils.calculateDistance(dropStation.location.latitude, dropStation.location.longitude, drivStart.latitude, drivStart.longitude);
          final dropDistToDest = MatchingUtils.calculateDistance(passDrop.latitude, passDrop.longitude, drivEnd.latitude, drivEnd.longitude);

          if (pickDistFromStation <= 15000 && dropDistToDest <= 15000) {
            final driverRoute = await _orsService.getRoute(drivStart, drivEnd);
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
      }

      for (var fm in firstMileOptions) {
        final arrivalAtDropStation = fm['arrival_at_board_station'] + trainDuration;

        for (var lm in lastMileOptions) {
          if (fm['type'] == 'Driver' && lm['type'] == 'Driver' && fm['driver_name'] == lm['driver_name']) continue;

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

            'pickup_name': currentPassengerTrip?['pickup_name'] ?? 'Pickup',
            'destination_name': currentPassengerTrip?['dropoff_name'] ?? 'Destination',
          });
        }
      }
    } catch (e) {
      print('Error generating mixed routes: $e');
    }

    if (_fetchId != currentFetchId) return;

    if (tempMixedRoutes.isEmpty) {
      tempMixedRoutes = _getHardcodedMixedData();
    }

    mixedMatchedRoutes = tempMixedRoutes;
    _hasFoundMixed = true;
    isMixedLoading = false;
    notifyListeners();
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
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

  List<Map<String, dynamic>> _getHardcodedDirectData() {
    return [
      {
        'id': 'hardcoded_id_1',
        'name': 'Hardcoded Driver A',
        'phone': 'Hardcoded Phone 123',
        'profile_image_url': null,
        'pickup_distance_km': 1.5,
        'driver_profile': {
          'depart_time': '08:00 AM',
        }
      },
      {
        'id': 'hardcoded_id_2',
        'name': 'Hardcoded Driver B',
        'phone': 'Hardcoded Phone 456',
        'profile_image_url': null,
        'pickup_distance_km': 3.2,
        'driver_profile': {
          'depart_time': '08:30 AM',
        }
      }
    ];
  }

  List<Map<String, dynamic>> _getHardcodedMixedData() {
    return [
      {
        'first_mile_type': 'Driver',
        'driver_a_name': 'Hardcoded Driver A',
        'driver_a_depart': '07:30 AM',
        'pickup_distance_km': 2.1,
        'walk_to_station_meters': 0.0,
        'walk_to_station_mins': 0,

        'board_station': 'Hardcoded Boarding Station A',
        'alight_station': 'Hardcoded Alight Station B',
        'is_interchange': false,
        'board_line_name': 'Hardcoded LRT Line',
        'board_line_short_name': 'HC', // --- ADDED ---
        'board_line_color': Colors.red,
        'alight_line_name': 'Hardcoded LRT Line',
        'alight_line_short_name': 'HC', // --- ADDED ---
        'alight_line_color': Colors.red,
        'train_duration_mins': 25,

        'last_mile_type': 'Walk',
        'driver_b_name': null,
        'driver_b_depart': null,
        'dropoff_distance_km': null,
        'walk_to_dest_meters': 800.0,
        'walk_to_dest_mins': 10,
        'pickup_name': 'Hardcoded Pickup Location',
        'destination_name': 'Hardcoded Dropoff Destination',
      },
      {
        'first_mile_type': 'Walk',
        'driver_a_name': null,
        'driver_a_depart': null,
        'pickup_distance_km': null,
        'walk_to_station_meters': 500.0,
        'walk_to_station_mins': 6,

        'board_station': 'Hardcoded Boarding Station C',
        'alight_station': 'Hardcoded Alight Station D',
        'is_interchange': true,
        'board_line_name': 'Hardcoded Start Line',
        'board_line_short_name': 'HC', // --- ADDED ---
        'board_line_color': Colors.green,
        'alight_line_name': 'Hardcoded End Line',
        'alight_line_short_name': 'HC', // --- ADDED ---
        'alight_line_color': Colors.orange,
        'train_duration_mins': 45,

        'last_mile_type': 'Driver',
        'driver_b_name': 'Hardcoded Driver B',
        'driver_b_depart': '08:45 AM',
        'dropoff_distance_km': 3.2,
        'walk_to_dest_meters': 0.0,
        'walk_to_dest_mins': 0,
        'pickup_name': 'Hardcoded Pickup Location',
        'destination_name': 'Hardcoded Dropoff Destination',
      }
    ];
  }
}