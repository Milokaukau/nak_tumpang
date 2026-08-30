import 'package:latlong2/latlong.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';
import 'package:nak_tumpang/core/entities/train_station.dart';
import 'package:nak_tumpang/core/data/train_station_data.dart';

class TransitUtils {
  static TrainStation? findNearestStation(LatLng point) {
    if (TrainStationData.stations.isEmpty) return null;

    TrainStation nearest = TrainStationData.stations.first;
    double minDistance = double.infinity;

    for (var station in TrainStationData.stations) {
      double dist = MatchingUtils.calculateDistance(
        point.latitude, point.longitude,
        station.location.latitude, station.location.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearest = station;
      }
    }
    return nearest;
  }

  static int calculateTrainDuration(TrainStation start, TrainStation end) {
    if (start.lineId != end.lineId) return 30;

    int stopsCount = (start.sequence - end.sequence).abs();
    return stopsCount * 3;
  }
}