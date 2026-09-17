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

  static const Set<String> waterLayers = {'ocean', 'marinearea'};

  bool get isWater => layer != null && waterLayers.contains(layer);
}
