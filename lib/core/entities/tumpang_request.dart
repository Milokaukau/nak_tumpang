import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nak_tumpang/core/entities/location_node.dart';

class NegotiatedField<T> {
  final T value;
  final String requestedBy;
  final bool isAccepted;

  NegotiatedField({
    required this.value,
    required this.requestedBy,
    required this.isAccepted,
  });

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'requested_by': requestedBy,
      'is_accepted': isAccepted,
    };
  }
}

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

    // HELPER: Safely convert Timestamps to Strings so the UI doesn't crash
    String parseStringOrTimestamp(dynamic val) {
      if (val is Timestamp) {
        // Converts to "YYYY-MM-DD HH:MM" format
        return val.toDate().toString().substring(0, 16);
      }
      return val?.toString() ?? '';
    }

    return TumpangRequest(
      id: documentId,
      passengerId: json['passenger_id'] ?? '',
      driverId: json['driver_id'] ?? '',
      status: json['status'] ?? 'negotiating',

      pickupLocation: NegotiatedLocation.fromJson(json['pickup_location'] ?? {}),
      dropoffLocation: NegotiatedLocation.fromJson(json['dropoff_location'] ?? {}),

      // Use the safe parser for date/time fields
      pickupTime: NegotiatedField<String>(
        value: parseStringOrTimestamp(json['pickup_time']?['value']),
        requestedBy: json['pickup_time']?['requested_by'] ?? '',
        isAccepted: json['pickup_time']?['is_accepted'] ?? false,
      ),
      subscriptionStartDate: NegotiatedField<String>(
        value: parseStringOrTimestamp(json['subscription_start_date']?['value']),
        requestedBy: json['subscription_start_date']?['requested_by'] ?? '',
        isAccepted: json['subscription_start_date']?['is_accepted'] ?? false,
      ),
      subscriptionEndDate: NegotiatedField<String>(
        value: parseStringOrTimestamp(json['subscription_end_date']?['value']),
        requestedBy: json['subscription_end_date']?['requested_by'] ?? '',
        isAccepted: json['subscription_end_date']?['is_accepted'] ?? false,
      ),

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