import 'package:supabase_flutter/supabase_flutter.dart';

class HomeSupabaseService {
  final _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchPassengerTrips(String userId) async {
    try {
      final response = await _supabase
          .from('passenger_trips')
          .select('*, users(*)')
          .eq('user_id', userId);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error in fetchPassengerTrips: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchDriverTrips() async {
    try {
      final response = await _supabase
          .from('driver_trips')
          .select('*, users(name, phone, avatar_url)');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error in fetchDriverTrips: $e");
      return [];
    }
  }

  // ==========================================
  // PASSENGER SUBSCRIPTIONS
  // ==========================================
  Future<List<Map<String, dynamic>>> fetchActiveSubscriptions(String passengerTripId) async {
    try {
      print('🔍 Fetching passenger subscriptions for Trip ID: $passengerTripId');

      final response = await _supabase
          .from('tumpang_subscription')
          .select('''
            *,
            driver_trips (
              users (
                name, phone, avatar_url 
              )
            )
          ''')
          .eq('passenger_trip_id', passengerTripId)
          .eq('status', 'active');

      return (response as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('⚠️ Error fetching passenger subscriptions: $e');
      return [];
    }
  }

  // ==========================================
  // DRIVER SUBSCRIPTIONS
  // ==========================================
  Future<List<Map<String, dynamic>>> fetchDriverActiveSubscriptions(String driverId) async {
    try {
      print('🔍 Fetching driver subscriptions for Driver ID: $driverId');
      final response = await _supabase
          .from('tumpang_subscription')
          .select('''
            *,
            passenger_trips (
              users (
                name, phone, avatar_url
              )
            ),
            driver_trips!inner(user_id)
          ''')
      // Using !inner join allows us to filter subscriptions by the driver's user ID directly
          .eq('driver_trips.user_id', driverId)
          .eq('status', 'active');

      return (response as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('⚠️ Error fetching driver subscriptions: $e');
      return [];
    }
  }
}