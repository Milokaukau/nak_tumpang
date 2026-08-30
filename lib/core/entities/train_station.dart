import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class TrainStation {
  final String id;
  final String name;
  final LatLng location;
  final String lineId;
  final String lineName;
  final Color lineColor;
  final int sequence;

  const TrainStation({
    required this.id,
    required this.name,
    required this.location,
    required this.lineId,
    required this.lineName,
    required this.lineColor,
    required this.sequence,
  });

  factory TrainStation.fromJson(Map<String, dynamic> json) {
    return TrainStation(
      id: json['id'],
      name: json['name'],
      location: LatLng(json['lat'], json['lng']),
      lineId: json['lineId'],
      lineName: json['lineName'],
      lineColor: Color(json['lineColor']),
      sequence: json['sequence'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'lat': location.latitude,
      'lng': location.longitude,
      'lineId': lineId,
      'lineName': lineName,
      'lineColor': lineColor.toARGB32(),
      'sequence': sequence,
    };
  }
}