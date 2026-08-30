import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';
import 'package:nak_tumpang/core/services/ors_service.dart';
import 'package:nak_tumpang/features/home/data/services/home_supabase_service.dart';

class HomeViewModel extends ChangeNotifier {
  String selectedFilter = 'Direct';
  Map<String, dynamic>? currentPassenger;
  Map<String, dynamic>? currentPassengerTrip;
  bool isLoading = true;

  final ORSService _orsService = ORSService();
  final HomeSupabaseService _homeService = HomeSupabaseService();

  List<Map<String, dynamic>> matchedDrivers = [];

  void setFilter(String option) {
    selectedFilter = option;
    notifyListeners();
  }

  Future<void> fetchMockPassenger() async {
    isLoading = true;
    notifyListeners();

    final trip = await _homeService.fetchPassengerTrip('usr_pass_9921');

    if (trip != null) {
      currentPassengerTrip = trip;
      currentPassenger = trip['users'];
      await _findAvailableDrivers();
    } else {
      print('❌ Failed to fetch passenger trip.');
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> _findAvailableDrivers() async {
    if (currentPassengerTrip == null) {
      print('❌ Passenger trip is null. Aborting.');
      return;
    }

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

    matchedDrivers.clear();
    notifyListeners();

    final driverTrips = await _homeService.fetchDriverTrips();
    print('🔍 Found ${driverTrips.length} drivers in Supabase.');

    for (var driverTrip in driverTrips) {
      final driverName = driverTrip['users']?['name'] ?? 'Unknown Driver';
      print('\n🚗 Evaluating Driver: $driverName');

      final driverDays = _extractActiveDays(driverTrip);

      // 1. Day Filter
      if (!MatchingUtils.hasOverlappingDays(passDays, driverDays)) {
        print('   -> ❌ Failed Day Filter');
        continue;
      }

      // 2. Time Filter (30 mins)
      final drivTime = _sqlTimeToMinutes(driverTrip['depart_time']);
      if ((drivTime - passTime).abs() > 30) {
        print('   -> ❌ Failed Time Filter (Pass: $passTime mins, Driv: $drivTime mins)');
        continue;
      }

      // 3. Rough Radius Filter
      final drivStart = LatLng(
          _parseDouble(driverTrip['depart_lat']),
          _parseDouble(driverTrip['depart_lng'])
      );

      final drivEnd = LatLng(
          _parseDouble(driverTrip['arrival_lat']),
          _parseDouble(driverTrip['arrival_lng'])
      );

      if (drivStart.latitude == 0 || drivEnd.latitude == 0) {
        print('   -> ❌ Failed: Missing or Null coordinates for this driver.');
        continue;
      }

      final pickDist = MatchingUtils.calculateDistance(
          passPick.latitude, passPick.longitude,
          drivStart.latitude, drivStart.longitude
      );
      final dropDist = MatchingUtils.calculateDistance(
          passDrop.latitude, passDrop.longitude,
          drivEnd.latitude, drivEnd.longitude
      );

      if (pickDist > 15000 || dropDist > 15000) {
        print('   -> ❌ Failed Radius Filter (Pick: ${pickDist.toStringAsFixed(0)}m, Drop: ${dropDist.toStringAsFixed(0)}m)');
        continue;
      }

      // 4. Strict Polyline Filter (Call ORS)
      try {
        final driverRoute = await _orsService.getRoute(drivStart, drivEnd);
        bool isMatch = MatchingUtils.isRouteMatch(passPick, passDrop, driverRoute, 800);

        if (isMatch) {
          print('   -> ✅ PERFECT MATCH!');
          matchedDrivers.add({
            'id': driverTrip['user_id'],
            'name': driverName,
            'pickup_distance_km': pickDist / 1000,
            'driver_profile': {
              'depart_time': _formatSqlTimeToUI(driverTrip['depart_time']),
            }
          });
        } else {
          print('   -> ❌ Failed ORS Route Match (Detour too far)');
        }
      } catch (e) {
        print('   -> ⚠️ ORS Route Error: $e');
        continue;
      }
    }

    print('\n🏁 Matching Complete. Found ${matchedDrivers.length} suitable drivers.');
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