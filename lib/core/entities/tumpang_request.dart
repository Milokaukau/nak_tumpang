// lib/core/entities/tumpang_request.dart

import 'package:nak_tumpang/core/entities/location_node.dart';

/// A generic wrapper for fields like 'fee' and 'pickup_time' that have a 'value'.
class NegotiatedField<T> {
  final T value;
  final String requestedBy;
  final bool isAccepted;

  NegotiatedField({
    required this.value,
    required this.requestedBy,
    required this.isAccepted,
  });

  factory NegotiatedField.fromJson(Map<String, dynamic> json) {
    return NegotiatedField<T>(
      value: json['value'] as T,
      requestedBy: json['requested_by'] ?? '',
      isAccepted: json['is_accepted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'requested_by': requestedBy,
      'is_accepted': isAccepted,
    };
  }
}

/// A specific wrapper for locations, as lat/lng/name are flattened
/// alongside 'is_accepted' and 'requested_by' in Firestore.
class NegotiatedLocation extends LocationNode {
  final String requestedBy;
  final bool isAccepted;

  NegotiatedLocation({
    required super.lat,
    required super.lng,
    required super.name,
    required this.requestedBy,
    required this.isAccepted,
  });

  factory NegotiatedLocation.fromJson(Map<String, dynamic> json) {
    return NegotiatedLocation(
      lat: (json['lat'] ?? 0.0).toDouble(),
      lng: (json['lng'] ?? 0.0).toDouble(),
      name: json['name'] ?? '',
      requestedBy: json['requested_by'] ?? '',
      isAccepted: json['is_accepted'] ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['requested_by'] = requestedBy;
    map['is_accepted'] = isAccepted;
    return map;
  }
}

/// The main Request document.
class TumpangRequest {
  final String id;
  final String passengerId;
  final String driverId;
  final String status;
  final NegotiatedLocation pickupLocation;
  final NegotiatedLocation dropoffLocation;
  final NegotiatedField<String> pickupTime;
  final NegotiatedField<double> fee;
  final NegotiatedField<String> subscriptionStartDate;
  final NegotiatedField<String> subscriptionEndDate;

  TumpangRequest({
    required this.id,
    required this.passengerId,
    required this.driverId,
    required this.status,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.pickupTime,
    required this.fee,
    required this.subscriptionStartDate,
    required this.subscriptionEndDate,
  });

  factory TumpangRequest.fromJson(String documentId, Map<String, dynamic> json) {
    return TumpangRequest(
      id: documentId,
      passengerId: json['passenger_id'] ?? '',
      driverId: json['driver_id'] ?? '',
      status: json['status'] ?? 'negotiating',

      // Parse nested objects
      pickupLocation: NegotiatedLocation.fromJson(json['pickup_location'] ?? {}),
      dropoffLocation: NegotiatedLocation.fromJson(json['dropoff_location'] ?? {}),

      // The API JSON showed dates and times as Strings
      pickupTime: NegotiatedField<String>.fromJson(json['pickup_time'] ?? {}),
      subscriptionStartDate: NegotiatedField<String>.fromJson(json['subscription_start_date'] ?? {}),
      subscriptionEndDate: NegotiatedField<String>.fromJson(json['subscription_end_date'] ?? {}),

      // Fee needs to be converted to double safely
      fee: NegotiatedField<double>(
        value: (json['fee']?['value'] ?? 0.0).toDouble(),
        requestedBy: json['fee']?['requested_by'] ?? '',
        isAccepted: json['fee']?['is_accepted'] ?? false,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'passenger_id': passengerId,
      'driver_id': driverId,
      'status': status,
      'pickup_location': pickupLocation.toJson(),
      'dropoff_location': dropoffLocation.toJson(),
      'pickup_time': pickupTime.toJson(),
      'fee': fee.toJson(),
      'subscription_start_date': subscriptionStartDate.toJson(),
      'subscription_end_date': subscriptionEndDate.toJson(),
    };
  }
}