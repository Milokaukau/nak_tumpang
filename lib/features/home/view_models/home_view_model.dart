import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';
import 'package:nak_tumpang/core/services/ors_service.dart';
import 'package:nak_tumpang/features/home/data/services/home_supabase_service.dart';

class HomeViewModel extends ChangeNotifier {
  String selectedFilter = 'Direct';
  Map<String, dynamic>? currentPassenger;
  Map<String, dynamic>? currentPassengerTrip;

  List<Map<String, dynamic>> availableTrips = [];

  bool isScreenLoading = true;    // For the initial boot
  bool isMatchingLoading = false; // For ORS calculations

  int _fetchId = 0;

  final ORSService _orsService = ORSService();
  final HomeSupabaseService _homeService = HomeSupabaseService();

  List<Map<String, dynamic>> matchedDrivers = [];

  void setFilter(String option) {
    selectedFilter = option;
    notifyListeners();
  }

  void changeTrip(String tripId) {
    // Prevent changing trips if we are still booting up
    if (isScreenLoading) return;

    final selected = availableTrips.firstWhere((t) => t['id'] == tripId);
    currentPassengerTrip = selected;
    _findAvailableDrivers();
  }

  Future<void> fetchMockPassenger() async {
    isScreenLoading = true;
    notifyListeners();

    final trips = await _homeService.fetchPassengerTrips('usr_pass_9921');

    if (trips.isNotEmpty) {
      availableTrips = trips;
      currentPassengerTrip = trips.first;
      currentPassenger = trips.first['users'];

      // Wait for the initial matching to finish
      await _findAvailableDrivers();
    } else {
      print('❌ Failed to fetch passenger trips.');
    }

    isScreenLoading = false;
    notifyListeners();
  }

  Future<void> _findAvailableDrivers() async {
    if (currentPassengerTrip == null) return;

    final currentFetchId = ++_fetchId;

    isMatchingLoading = true;
    matchedDrivers.clear();
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

        bool isMatch = MatchingUtils.isRouteMatch(passPick, passDrop, driverRoute, 800);

        if (isMatch) {
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

    matchedDrivers = tempMatchedDrivers;
    isMatchingLoading = false;
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
}