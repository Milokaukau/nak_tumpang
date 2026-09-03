class ApiConstants {
  // ORS Endpoints
  static const String orsDrivingEndpoint = 'https://api.openrouteservice.org/v2/directions/driving-car';
  static const String orsWalkingEndpoint = 'https://api.openrouteservice.org/v2/directions/foot-walking';
  // Pelias-backed "as you type" search — lighter weight than /geocode/search,
  // built for partial queries like a user still typing an address.
  static const String orsAutocompleteEndpoint = 'https://api.openrouteservice.org/geocode/autocomplete';
  // Coordinates -> human-readable place (e.g. after a map pin drop).
  static const String orsReverseEndpoint = 'https://api.openrouteservice.org/geocode/reverse';

  // Data.gov.my Endpoints
  static const String gtfsPrasaranaEndpoint = 'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl';
}