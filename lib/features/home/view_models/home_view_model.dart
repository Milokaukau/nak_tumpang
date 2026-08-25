import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';
import 'package:nak_tumpang/core/services/ors_service.dart';

class HomeViewModel extends ChangeNotifier {
  String selectedFilter = 'Direct';
  Map<String, dynamic>? currentPassenger;
  bool isLoading = true;

  final ORSService _orsService = ORSService();
  List<Map<String, dynamic>> matchedDrivers = [];

  void setFilter(String option) {
    selectedFilter = option;
    notifyListeners();
  }

  Future<void> fetchMockPassenger() async {
    isLoading = true;
    notifyListeners();

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc('usr_pass_9921').get();
      if (doc.exists) {
        currentPassenger = doc.data();
        currentPassenger?['id'] = doc.id;

        await _findAvailableDrivers();
      }
    } catch (e) {
      print("Error during fetchMockPassenger(): $e");
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> _findAvailableDrivers() async {
    final passProfile = currentPassenger?['passenger_profile'];
    final passDays = currentPassenger?['active_days'];

    final passPick = LatLng(passProfile['desired_pickup_location']['lat'], passProfile['desired_pickup_location']['lng']);
    final passDrop = LatLng(passProfile['desired_dropoff_location']['lat'], passProfile['desired_dropoff_location']['lng']);
    final passTime = MatchingUtils.timeToMinutes(passProfile['desired_pickup_time']);

    matchedDrivers.clear();
    notifyListeners();

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .get();

      for (var doc in snapshot.docs) {
        final driver = doc.data();
        final drivProfile = driver['driver_profile'];

        // 1. Day Filter
        if (!MatchingUtils.hasOverlappingDays(passDays, driver['active_days'])) continue;

        // 2. Time Filter (30 mins)
        final drivTime = MatchingUtils.timeToMinutes(drivProfile['depart_time']);
        if ((drivTime - passTime).abs() > 30) continue;

        // 3. Rough Radius Filter
        final pickDist = MatchingUtils.calculateDistance(
            passPick.latitude, passPick.longitude,
            drivProfile['start_location']['lat'], drivProfile['start_location']['lng']
        );
        final dropDist = MatchingUtils.calculateDistance(
            passDrop.latitude, passDrop.longitude,
            drivProfile['end_location']['lat'], drivProfile['end_location']['lng']
        );

        if (pickDist > 15000 || dropDist > 15000) continue;

        // 4. Strict Polyline Filter (Call ORS)
        final drivStart = LatLng(drivProfile['start_location']['lat'], drivProfile['start_location']['lng']);
        final drivEnd = LatLng(drivProfile['end_location']['lat'], drivProfile['end_location']['lng']);

        final driverRoute = await _orsService.getRoute(drivStart, drivEnd);

        bool isMatch = MatchingUtils.isRouteMatch(passPick, passDrop, driverRoute, 800);

        if (isMatch) {
          driver['pickup_distance_km'] = pickDist / 1000;
          matchedDrivers.add(driver);
        }
      }
    } catch (e) {
      print("Error during _findAvailableDrivers(): $e");
    }

    notifyListeners();
  }
}