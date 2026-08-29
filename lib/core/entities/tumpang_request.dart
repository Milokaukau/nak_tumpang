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

  factory NegotiatedLocation.fromJson(Map<String, dynamic> json, String prefix) {
    return NegotiatedLocation(
      lat: (json['${prefix}_lat'] ?? 0.0).toDouble(),
      lng: (json['${prefix}_lng'] ?? 0.0).toDouble(),
      name: json['${prefix}_name']?.toString() ?? '',
      requestedBy: json['${prefix}_requested_by']?.toString() ?? '',
      isAccepted: json['${prefix}_is_accepted'] ?? false,
    );
  }
}

class TumpangRequest {
  final String id;
  final String passengerTripId;
  final String driverTripId;
  final String status;
  final NegotiatedLocation pickupLocation;
  final NegotiatedLocation dropoffLocation;
  final NegotiatedField<String> pickupTime;
  final NegotiatedField<double> fee;
  final NegotiatedField<String> subscriptionStartDate;
  final NegotiatedField<String> subscriptionEndDate;

  TumpangRequest({
    required this.id,
    required this.passengerTripId,
    required this.driverTripId,
    required this.status,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.pickupTime,
    required this.fee,
    required this.subscriptionStartDate,
    required this.subscriptionEndDate,
  });

  // Accepts a single flat map from PostgreSQL row
  factory TumpangRequest.fromJson(Map<String, dynamic> json) {
    return TumpangRequest(
      id: json['id']?.toString() ?? '',
      passengerTripId: json['passenger_trip_id']?.toString() ?? '',
      driverTripId: json['driver_trip_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'negotiating',

      pickupLocation: NegotiatedLocation.fromJson(json, 'pickup'),
      dropoffLocation: NegotiatedLocation.fromJson(json, 'dropoff'),

      pickupTime: NegotiatedField<String>(
        value: json['pickup_time']?.toString() ?? '',
        requestedBy: json['pickup_time_requested_by']?.toString() ?? '',
        isAccepted: json['pickup_time_is_accepted'] ?? false,
      ),

      fee: NegotiatedField<double>(
        value: (json['fee'] != null) ? double.parse(json['fee'].toString()) : 0.0,
        requestedBy: json['fee_requested_by']?.toString() ?? '',
        isAccepted: json['fee_is_accepted'] ?? false,
      ),

      subscriptionStartDate: NegotiatedField<String>(
        value: json['sub_start_date']?.toString() ?? '',
        requestedBy: json['sub_start_requested_by']?.toString() ?? '',
        isAccepted: json['sub_start_is_accepted'] ?? false,
      ),

      subscriptionEndDate: NegotiatedField<String>(
        value: json['sub_end_date']?.toString() ?? '',
        requestedBy: json['sub_end_requested_by']?.toString() ?? '',
        isAccepted: json['sub_end_is_accepted'] ?? false,
      ),
    );
  }

  // Exports to flat PostgreSQL table columns
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'passenger_trip_id': passengerTripId,
      'driver_trip_id': driverTripId,
      'status': status,

      'pickup_lat': pickupLocation.lat,
      'pickup_lng': pickupLocation.lng,
      'pickup_name': pickupLocation.name,
      'pickup_requested_by': pickupLocation.requestedBy,
      'pickup_is_accepted': pickupLocation.isAccepted,

      'dropoff_lat': dropoffLocation.lat,
      'dropoff_lng': dropoffLocation.lng,
      'dropoff_name': dropoffLocation.name,
      'dropoff_requested_by': dropoffLocation.requestedBy,
      'dropoff_is_accepted': dropoffLocation.isAccepted,

      'pickup_time': pickupTime.value,
      'pickup_time_requested_by': pickupTime.requestedBy,
      'pickup_time_is_accepted': pickupTime.isAccepted,

      'fee': fee.value,
      'fee_requested_by': fee.requestedBy,
      'fee_is_accepted': fee.isAccepted,

      'sub_start_date': subscriptionStartDate.value,
      'sub_start_requested_by': subscriptionStartDate.requestedBy,
      'sub_start_is_accepted': subscriptionStartDate.isAccepted,

      'sub_end_date': subscriptionEndDate.value,
      'sub_end_requested_by': subscriptionEndDate.requestedBy,
      'sub_end_is_accepted': subscriptionEndDate.isAccepted,
    };
  }
}