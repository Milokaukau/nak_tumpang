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
  Future<List<Map<String, dynamic>>> fetchAllPassengerSubscriptions(String userId) async {
    try {
      print('🔍 Fetching all passenger subscriptions for User ID: $userId');

      final response = await _supabase
          .from('tumpang_subscription')
          .select('''
            *,
            driver_trips (
              users (
                name, phone, avatar_url 
              )
            ),
            passenger_trips!inner(user_id) 
          ''')
      // Filters for ALL trips belonging to this user
          .eq('passenger_trips.user_id', userId)
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
  Future<List<Map<String, dynamic>>> fetchDriverActiveSubscriptions(String userId) async {
    try {
      print('🔍 Fetching all driver subscriptions for User ID: $userId');

      final response = await _supabase
          .from('tumpang_subscription')
          .select('''
            *,
            passenger_trips (
              users (
                name, phone, avatar_url 
              )
            ),
            driver_trips!inner(
              user_id,
              depart_lat, depart_lng,
              arrival_lat, arrival_lng
            ) 
          ''')
          .eq('driver_trips.user_id', userId)
          .eq('status', 'active');

      return (response as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('⚠️ Error fetching driver subscriptions: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> fetchUserProfile(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select('id, name, phone, avatar_url, role')
          .eq('id', userId)
          .single();

      return response;
    } catch (e) {
      print('⚠️ Error fetching user profile: $e');
      return null;
    }
  }
}