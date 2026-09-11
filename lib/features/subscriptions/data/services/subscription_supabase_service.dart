import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class SubscriptionSupabaseService {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List && value.isNotEmpty && value.first is Map<String, dynamic>) {
      return value.first as Map<String, dynamic>;
    }
    return null;
  }

  Map<String, dynamic> _normalizeSubscription(Map<String, dynamic> sub, String currentRole) {
    final passengerTrip = _asMap(sub['passenger_trips']);
    final driverTrip = _asMap(sub['driver_trips']);
    final passengerUser = _asMap(passengerTrip?['users']);
    final driverUser = _asMap(driverTrip?['users']);

    final driverId = driverUser?['id'] ?? driverTrip?['user_id'] ?? '';
    final driverName = driverUser?['name'] ?? 'Driver';
    final driverPhone = driverUser?['phone'] ?? '';
    final driverImageUrl = driverUser?['profile_image_url'] ?? driverUser?['imageUrl'];

    final passengerId = passengerUser?['id'] ?? passengerTrip?['user_id'] ?? '';
    final passengerName = passengerUser?['name'] ?? 'Passenger';
    final passengerPhone = passengerUser?['phone'] ?? '';
    final passengerImageUrl = passengerUser?['profile_image_url'] ?? passengerUser?['imageUrl'];

    final pickupLocation = sub['pickup_location'] ??
        passengerTrip?['pickup_location'] ??
        passengerTrip?['pickup_name'] ??
        driverTrip?['pickup_location'] ??
        driverTrip?['pickup_name'] ??
        '';

    final dropoffLocation = sub['dropoff_location'] ??
        sub['destination_location'] ??
        passengerTrip?['dropoff_location'] ??
        passengerTrip?['destination_location'] ??
        passengerTrip?['destination_name'] ??
        passengerTrip?['dropoff_name'] ??
        driverTrip?['dropoff_location'] ??
        driverTrip?['destination_location'] ??
        driverTrip?['destination_name'] ??
        driverTrip?['dropoff_name'] ??
        '';

    final pickupTime = sub['pickup_time'] ?? passengerTrip?['pickup_time'] ?? driverTrip?['pickup_time'] ?? '';

    final isPassenger = currentRole == 'passenger';
    final otherName = isPassenger ? driverName : passengerName;
    final otherPhone = isPassenger ? driverPhone : passengerPhone;
    final otherImageUrl = isPassenger ? driverImageUrl : passengerImageUrl;

    return {
      ...sub,
      'driver_id': driverId,
      'driver_name': driverName,
      'driver_phone': driverPhone,
      'driver_image_url': driverImageUrl,
      'passenger_id': passengerId,
      'passenger_name': passengerName,
      'passenger_phone': passengerPhone,
      'passenger_image_url': passengerImageUrl,
      'name': otherName,
      'phone': otherPhone,
      'imageUrl': otherImageUrl,
      'pickup_location': pickupLocation,
      'dropoff_location': dropoffLocation,
      'pickup_time': pickupTime,
      'driver_trips': driverTrip,
      'passenger_trips': passengerTrip,
    };
  }

  Future<void> _checkAndAutoExpire(String subscriptionId, String endDateStr) async {
    final endDate = DateTime.tryParse(endDateStr);
    if (endDate == null) return;
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    if (endDate.isBefore(todayDateOnly)) {
      await _supabase.from('tumpang_subscription').update({
        'status': 'inactive',
        'ended_by': 'natural',
        'ended_at': DateTime.now().toIso8601String(),
        'deposit_refunded': true,
      }).eq('id', subscriptionId);
    }
  }

  Future<bool> extendSubscription({
    required String subscriptionId,
    required DateTime newEndDate,
  }) async {
    try {
      await _supabase.from('tumpang_subscription').update({
        'subscription_end_date': _formatDate(newEndDate),
        'status': 'active',
        'ended_by': null,
        'ended_at': null,
      }).eq('id', subscriptionId);
      return true;
    } catch (e) {
      print('Error in extendSubscription: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchSubscriptions({
    required String userId,
    required String role,
  }) async {
    try {
      final tripTable = role == 'passenger' ? 'passenger_trips' : 'driver_trips';
      final tripIdField = role == 'passenger' ? 'passenger_trip_id' : 'driver_trip_id';

      final tripsResponse = await _supabase
          .from(tripTable)
          .select('id')
          .eq('user_id', userId);

      final tripIds = (tripsResponse as List)
          .map((t) => t['id'] as String)
          .toList();

      if (tripIds.isEmpty) return [];

      final response = await _supabase
          .from('tumpang_subscription')
          .select('''
            *,
            passenger_trips:passenger_trip_id (*, users (*)),
            driver_trips:driver_trip_id (*, users (*))
          ''')
          .inFilter(tripIdField, tripIds);

      final rawList = List<Map<String, dynamic>>.from(response);

      // Auto-expire any active subscription whose end date has passed
      for (var sub in rawList) {
        if (sub['status'] == 'active' && sub['subscription_end_date'] != null) {
          await _checkAndAutoExpire(sub['id'], sub['subscription_end_date']);
        }
      }

      // Re-fetch so status reflects any auto-expiry that just happened
      final refreshedResponse = await _supabase
          .from('tumpang_subscription')
          .select('''
            *,
            passenger_trips:passenger_trip_id (*, users (*)),
            driver_trips:driver_trip_id (*, users (*))
          ''')
          .inFilter(tripIdField, tripIds);

      final refreshedList = List<Map<String, dynamic>>.from(refreshedResponse);
      return refreshedList.map((sub) => _normalizeSubscription(sub, role)).toList();
    } catch (e) {
      print("Error in fetchSubscriptions: $e");
      return [];
    }
  }

  Future<bool> hasActiveException(String subscriptionId) async {
    try {
      final response = await _supabase
          .from('tumpang_exception')
          .select('id')
          .eq('tumpang_subscription_id', subscriptionId)
          .eq('status', 'active');
      return (response as List).isNotEmpty;
    } catch (e) {
      print("Error in hasActiveException: $e");
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchExceptionsForSubscription(String subscriptionId) async {
    try {
      final response = await _supabase
          .from('tumpang_exception')
          .select()
          .eq('tumpang_subscription_id', subscriptionId)
          .eq('status', 'active')
          .order('start_date', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error in fetchExceptionsForSubscription: $e");
      return [];
    }
  }

  Future<bool> cancelException(String exceptionId) async {
    try {
      await _supabase.from('tumpang_exception').delete().eq('id', exceptionId);
      return true;
    } catch (e) {
      print("Error in cancelException: $e");
      return false;
    }
  }

  Future<bool> cancelSubscription({
    required String subscriptionId,
    required String cancelledByRole,
    String? reason,
  }) async {
    try {
      final updateData = {
        'status': 'inactive',
        'ended_by': cancelledByRole.toLowerCase(),
        'ended_at': DateTime.now().toIso8601String(),
      };

      if (reason != null && reason.isNotEmpty) {
        updateData['cancellation_reason'] = reason;
      }

      await Supabase.instance.client
          .from('tumpang_subscription')
          .update(updateData)
          .eq('id', subscriptionId);

      return true;
    } catch (e) {
      debugPrint('Supabase Error cancelling subscription: $e');
      return false;
    }
  }

  Future<bool> updateException({
    required String exceptionId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    try {
      await _supabase.from('tumpang_exception').update({
        'start_date': _formatDate(startDate),
        'end_date': _formatDate(endDate),
        'reason': reason,
      }).eq('id', exceptionId);
      return true;
    } catch (e) {
      print("Error in updateException: $e");
      return false;
    }
  }

  Future<String?> createExtensionRequest({
    required Map<String, dynamic> oldSubscription,
    required DateTime newStartDate,
    required DateTime newEndDate,
  }) async {
    final supabase = Supabase.instance.client;

    try {
      // Generate a unique ID since the schema doesn't have a default value
      final String newRequestId = 'REQ-${DateTime.now().millisecondsSinceEpoch}';

      // Insert valid payload matching the EXACT schema of tumpang_request
      final response = await supabase.from('tumpang_request').insert({
        'id': newRequestId,
        'passenger_trip_id': oldSubscription['passenger_trip_id'],
        'driver_trip_id': oldSubscription['driver_trip_id'],

        // Pickups
        'pickup_name': oldSubscription['pickup_location'],
        'pickup_lat': oldSubscription['pickup_lat'],
        'pickup_lng': oldSubscription['pickup_lng'],

        // Dropoffs
        'dropoff_name': oldSubscription['dropoff_location'],
        'dropoff_lat': oldSubscription['dropoff_lat'],
        'dropoff_lng': oldSubscription['dropoff_lng'],

        // Time & Dates
        'pickup_time': oldSubscription['pickup_time'],
        'sub_start_date': newStartDate.toIso8601String().split('T')[0],
        'sub_end_date': newEndDate.toIso8601String().split('T')[0],

        // Extension Data
        'status': 'pending',
        'is_extension': true,
        'extends_subscription_id': oldSubscription['id'],
        'extension_type': 'extend',

        // Carry over the existing fee
        'fee': oldSubscription['fee'],
      }).select('id').maybeSingle();

      if (response == null) {
        print('❌ Failed to create request: No ID returned');
        return null;
      }

      return response['id'] as String; // Return the new ID
    } catch (e, stackTrace) {
      print('❌ Service Extension Insert Error: $e');
      print(stackTrace);
      return null;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}