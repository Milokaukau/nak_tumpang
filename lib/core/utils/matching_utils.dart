import 'package:latlong2/latlong.dart';

class MatchingUtils {
  static const Distance _distance = Distance();

  static double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return _distance.as(
      LengthUnit.Meter,
      LatLng(lat1, lng1),
      LatLng(lat2, lng2),
    ).toDouble();
  }

  static int timeToMinutes(String timeString) {
    final parts = timeString.split(' ');
    final time = parts[0].split(':');
    int hours = int.parse(time[0]);
    int minutes = int.parse(time[1]);

    if (parts[1] == 'PM' && hours != 12) hours += 12;
    if (parts[1] == 'AM' && hours == 12) hours = 0;

    return (hours * 60) + minutes;
  }

  static bool hasOverlappingDays(Map<String, dynamic> passDays, Map<String, dynamic> drivDays) {
    for (String day in passDays.keys) {
      if (passDays[day] == true && drivDays[day] == true) {
        return true;
      }
    }
    return false;
  }

  static bool isRouteMatch(
      LatLng passPick,
      LatLng passDrop,
      List<LatLng> driverRoute,
      double maxDetourMeters,
      ) {
    if (driverRoute.isEmpty) return false;

    double minPickDist = double.infinity;
    int pickIndex = -1;

    double minDropDist = double.infinity;
    int dropIndex = -1;

    // Find the closest point on the driver's route for both pickup and dropoff
    for (int i = 0; i < driverRoute.length; i++) {
      final point = driverRoute[i];

      final pickDist = _distance.as(LengthUnit.Meter, passPick, point).toDouble();
      if (pickDist < minPickDist) {
        minPickDist = pickDist;
        pickIndex = i;
      }

      final dropDist = _distance.as(LengthUnit.Meter, passDrop, point).toDouble();
      if (dropDist < minDropDist) {
        minDropDist = dropDist;
        dropIndex = i;
      }
    }

    // 1. Both points must be within the maximum allowed detour distance
    if (minPickDist > maxDetourMeters || minDropDist > maxDetourMeters) return false;

    // 2. Sequence check: Driver must reach pickup before dropoff
    if (pickIndex > dropIndex) return false;

    return true;
  }
}