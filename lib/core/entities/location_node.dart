class LocationNode {
  final double lat;
  final double lng;
  final String name;

  LocationNode({
    required this.lat,
    required this.lng,
    required this.name,
  });

  factory LocationNode.fromJson(Map<String, dynamic> json) {
    return LocationNode(
      lat: (json['lat'] ?? 0.0).toDouble(),
      lng: (json['lng'] ?? 0.0).toDouble(),
      name: json['name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
      'name': name,
    };
  }
}