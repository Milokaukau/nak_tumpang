// result -> real pace w coordinates
class GeocodedPlace {
  final String label;
  final double latitude;
  final double longitude;

  final String? layer;

  const GeocodedPlace({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.layer,
  });


  // layers pelias use for waters than actual land
  static const Set<String> waterLayers = {'ocean', 'marinearea'};

  bool get isWater => layer != null && waterLayers.contains(layer);
}
