/// A single result from the ORS geocoding autocomplete API — a real,
/// resolvable place with coordinates, not just free-typed text.
class GeocodedPlace {
  final String label;
  final double latitude;
  final double longitude;

  /// The Pelias/whosonfirst "layer" this result belongs to (e.g.
  /// 'venue', 'address', 'locality', 'ocean', 'marinearea'), when known.
  /// Null when the place didn't come from a geocoding response that
  /// includes one (e.g. the raw "lat, lng" fallback label).
  final String? layer;

  const GeocodedPlace({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.layer,
  });

  /// Layers Pelias uses for seas/oceans/straits rather than actual land —
  /// results tagged with these are things like "South China Sea" or
  /// "Strait of Malacca", not a real pickup/drop-off point.
  static const Set<String> waterLayers = {'ocean', 'marinearea'};

  bool get isWater => layer != null && waterLayers.contains(layer);
}
