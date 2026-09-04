/// A generous bounding box around Malaysia (covers both Peninsular
/// Malaysia and East Malaysia / Sabah & Sarawak). Used to reject a
/// picked location — from search, a map tap, or "use my location" — that
/// falls outside the country, since drivers/passengers should only be
/// setting up trips within Malaysia.
///
/// This is a rectangle, not the real country outline, so it's
/// intentionally a bit loose (it also covers slivers of the sea and
/// neighbouring countries near the borders) rather than a precise
/// polygon — good enough for a client-side sanity check. The ORS
/// `boundary.country=MYS` param already does exact server-side
/// filtering for text search results; this covers the cases that don't
/// go through that endpoint (map taps, GPS location).
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
