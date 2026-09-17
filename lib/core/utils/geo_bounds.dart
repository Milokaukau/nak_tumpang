class MalaysiaBounds {
  static const double minLat = 0.85;
  static const double maxLat = 7.5;
  static const double minLng = 99.5;
  static const double maxLng = 119.5;

  static bool contains(double lat, double lng) {
    return lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
  }

  static const String outsideMessage = 'Please select a location within Malaysia.';
}
