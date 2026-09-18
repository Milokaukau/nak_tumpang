import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/features/subscriptions/data/services/subscription_supabase_service.dart';

class TripSupabaseService {
  final _supabase = Supabase.instance.client;

  Future<String?> getUserRole(String userId) async {
    try {
      final res = await _supabase.from('users').select('role').eq('id', userId).single();
      return res['role'] as String?;
    } catch (e) {
      print('⚠️ Error fetching role: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchMyTrips(String userId, String role) async {
    final table = role == 'driver' ? 'driver_trips' : 'passenger_trips';
    try {
      final response = await _supabase.from(table).select().eq('user_id', userId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('⚠️ Error fetching trips: $e');
      return [];
    }
  }

  Future<Set<String>> fetchActiveSubbedTripIds(String userId, String role) async {
    final tripKey = role == 'driver' ? 'driver_trip_id' : 'passenger_trip_id';
    final tripTable = role == 'driver' ? 'driver_trips' : 'passenger_trips';

    try {
      final response = await _supabase
          .from('tumpang_subscription')
          .select('$tripKey, $tripTable!inner(user_id)')
          .eq('$tripTable.user_id', userId)
          .eq('status', 'active');

      return (response as List)
          .map((sub) => sub[tripKey])
          .where((id) => id != null)
          .map((id) => id.toString())
          .toSet();
    } catch (e) {
      print('⚠️ Error fetching active subscriptions: $e');
      return {};
    }
  }

  Future<Set<String>> fetchNegotiatingTripIds(String userId, String role) async {
    final tripKey = role == 'driver' ? 'driver_trip_id' : 'passenger_trip_id';
    final tripTable = role == 'driver' ? 'driver_trips' : 'passenger_trips';

    try {
      final response = await _supabase
          .from('tumpang_request')
          .select('$tripKey, $tripTable!inner(user_id)')
          .eq('$tripTable.user_id', userId)
          .or('status.eq.pending,status.eq.negotiating');

      return (response as List)
          .map((req) => req[tripKey])
          .where((id) => id != null)
          .map((id) => id.toString())
          .toSet();
    } catch (e) {
      print('⚠️ Error fetching negotiating trips: $e');
      return {};
    }
  }

  Future<void> deleteTrip(String tripId, String role) async {
    final table = role == 'driver' ? 'driver_trips' : 'passenger_trips';
    await _supabase.from(table).delete().eq('id', tripId);
  }

  Future<void> insertTrip(Map<String, dynamic> tripData, String role) async {
    final table = role == 'driver' ? 'driver_trips' : 'passenger_trips';
    await _supabase.from(table).insert(tripData);
  }

  Future<String?> findNegotiatingRequestId(String tripId) async {
    try {
      final resList = await _supabase
          .from('tumpang_request')
          .select('id')
          .or('driver_trip_id.eq.$tripId,passenger_trip_id.eq.$tripId')
          .inFilter('status', ['pending', 'negotiating'])
          .limit(1);

      if ((resList as List).isEmpty) return null;
      return resList.first['id'] as String;
    } catch (e) {
      print('⚠️ Error finding negotiating request: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchActiveSubscriptionForTrip(String tripId, String role) async {
    try {
      final resList = await _supabase
          .from('tumpang_subscription')
          .select('*, driver_trips(*, users(*)), passenger_trips(*, users(*))')
          .or('driver_trip_id.eq.$tripId,passenger_trip_id.eq.$tripId')
          .eq('status', 'active')
          .limit(1);

      if ((resList as List).isEmpty) return null;
      return SubscriptionSupabaseService().normalizeSubscription(resList.first, role);
    } catch (e) {
      print('⚠️ Error finding active subscription: $e');
      rethrow;
    }
  }

  Future<void> updateTrip(String tripId, Map<String, dynamic> tripData, String role) async {
    final table = role == 'driver' ? 'driver_trips' : 'passenger_trips';
    await _supabase.from(table).update(tripData).eq('id', tripId);
  }
}