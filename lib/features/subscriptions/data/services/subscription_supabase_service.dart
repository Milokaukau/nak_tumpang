import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionSupabaseService {
  final _supabase = Supabase.instance.client;

  /// Fetches all subscriptions where the given user is either the passenger or driver.
  Future<List<Map<String, dynamic>>> fetchSubscriptions({
    required String userId,
    required String role,
  }) async {
    try {
      final tripTable = role == 'passenger' ? 'passenger_trips' : 'driver_trips';
      final tripIdField = role == 'passenger' ? 'passenger_trip_id' : 'driver_trip_id';

      print('🔍 Step 1: querying $tripTable for user_id=$userId');
      final tripsResponse = await _supabase
          .from(tripTable)
          .select('id')
          .eq('user_id', userId);
      print('🔍 Step 1 result: $tripsResponse');

      final tripIds = (tripsResponse as List)
          .map((t) => t['id'] as String)
          .toList();
      print('🔍 tripIds: $tripIds');

      if (tripIds.isEmpty) return [];

      print('🔍 Step 2: querying tumpang_subscription where $tripIdField in $tripIds');
      final response = await _supabase
          .from('tumpang_subscription')
          .select('*, passenger_trips(*, users(*)), driver_trips(*, users(*))')
          .inFilter(tripIdField, tripIds);
      print('🔍 Step 2 result: $response');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error in fetchSubscriptions: $e");
      return [];
    }
  }

  /// Checks whether a subscription has any active (non-cancelled) exceptions.
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

  /// Fetches all active exceptions for a subscription, most recent first.
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
      await _supabase
          .from('tumpang_exception')
          .update({'status': 'cancelled'})
          .eq('id', exceptionId);
      return true;
    } catch (e) {
      print("Error in cancelException: $e");
      return false;
    }
  }

  /// Cancels a subscription. Deposit refund logic depends on who cancels:
  /// - driver cancels early -> refund
  /// - passenger cancels early -> forfeit
  Future<bool> cancelSubscription({
    required String subscriptionId,
    required String cancelledByRole, // 'passenger' or 'driver'
  }) async {
    try {
      final refund = cancelledByRole == 'driver';
      await _supabase.from('tumpang_subscription').update({
        'status': 'inactive',
        'ended_by': cancelledByRole,
        'ended_at': DateTime.now().toIso8601String(),
        'deposit_refunded': refund,
      }).eq('id', subscriptionId);
      return true;
    } catch (e) {
      print("Error in cancelSubscription: $e");
      return false;
    }
  }
}