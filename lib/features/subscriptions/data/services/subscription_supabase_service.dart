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

  Map<String, dynamic> normalizeSubscription(Map<String, dynamic> sub, String currentRole) {
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
      return refreshedList.map((sub) => normalizeSubscription(sub, role)).toList();
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

  // 1. UPDATE your existing cancelSubscription method to accept 'otherUserId'
  Future<bool> cancelSubscription({
    required String subscriptionId,
    required String cancelledByRole,
    required String otherUserId,
    String? reason,
  }) async {
    // ==========================================
    // 1. UPDATE THE SUBSCRIPTION STATUS
    // ==========================================
    try {
      final updateData = {
        'status': 'inactive',
        'ended_by': cancelledByRole.toLowerCase(),
        'ended_at': DateTime.now().toIso8601String(),
      };

      if (reason != null && reason.isNotEmpty) {
        updateData['cancellation_reason'] = reason;
      }

      await _supabase.from('tumpang_subscription').update(updateData).eq('id', subscriptionId);

    } catch (e) {
      debugPrint('🚨 Supabase Error cancelling subscription: $e');
      return false; // If the cancel fails, stop here
    }

    // ==========================================
    // 2. INSERT THE NOTIFICATION
    // ==========================================
    try {
      if (otherUserId.isEmpty) {
        debugPrint('🚨 NOTIF ERROR: otherUserId is empty! Supabase will reject this because it needs a valid UUID.');
      } else {
        // Generate a unique string ID for the notification
        final String notifId = 'NOTIF-${DateTime.now().millisecondsSinceEpoch}';

        await _supabase.from('tumpang_notifications').insert({
          'id': notifId,
          'target_user_id': otherUserId,
          'title': 'Subscription Cancelled',
          'message': 'Your Tumpang subscription has been cancelled by the ${cancelledByRole.toLowerCase()}.',
          'type': 'cancellation',
          'is_read': false,
          'subscription_id': subscriptionId,
        });

        debugPrint('✅ NOTIF SUCCESS: Notification inserted for user: $otherUserId with subscription_id: $subscriptionId');
      }
    } catch (e) {
      debugPrint('🚨 NOTIF INSERT ERROR: $e');
    }

    return true;
  }

  // 2. ADD THIS METHOD to fetch unread alerts
  Future<List<Map<String, dynamic>>> fetchUnreadNotifications(String userId) async {
    try {
      final response = await _supabase
          .from('tumpang_notifications')
          .select()
          .eq('target_user_id', userId)
          .eq('is_read', false)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error fetching notifications: $e");
      return [];
    }
  }

  // 3. ADD THIS METHOD to mark them as read so they don't show twice
  Future<void> markNotificationsAsRead(List<String> notificationIds) async {
    if (notificationIds.isEmpty) return;
    try {
      await _supabase
          .from('tumpang_notifications')
          .update({'is_read': true})
          .inFilter('id', notificationIds);
    } catch (e) {
      print("Error marking notifications read: $e");
    }
  }

  Future<bool> updateException({
    required String exceptionId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    required String otherUserId,
    String? subscriptionId, // NEW
  }) async {
    try {
      await _supabase.from('tumpang_exception').update({
        'start_date': _formatDate(startDate),
        'end_date': _formatDate(endDate),
        'reason': reason,
      }).eq('id', exceptionId);

      final String notifId = 'NOTIF-${DateTime.now().millisecondsSinceEpoch}';
      await _supabase.from('tumpang_notifications').insert({
        'id': notifId,
        'target_user_id': otherUserId,
        'title': 'Schedule Change Updated',
        'message': 'A schedule exception has been modified for dates ${_formatDate(startDate)} to ${_formatDate(endDate)}.',
        'type': 'exception',
        'is_read': false,
        'subscription_id': subscriptionId, // NEW
      });

      return true;
    } catch (e) {
      print("Error in updateException: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchSubscriptionById(String subscriptionId, String role) async {
    try {
      final response = await _supabase
          .from('tumpang_subscription')
          .select('''
          *,
          passenger_trips:passenger_trip_id (*, users (*)),
          driver_trips:driver_trip_id (*, users (*))
        ''')
          .eq('id', subscriptionId)
          .maybeSingle();

      if (response == null) return null;
      return normalizeSubscription(response, role);
    } catch (e) {
      print('Error in fetchSubscriptionById: $e');
      return null;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}