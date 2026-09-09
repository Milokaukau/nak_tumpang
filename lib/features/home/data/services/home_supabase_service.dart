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

  Future<List<Map<String, dynamic>>> fetchAllPassengerSubscriptions(String userId) async {
    try {
      final response = await _supabase
          .from('tumpang_subscription')
          .select('''
            *,
            driver_trips (
              users (
                name, phone, avatar_url 
              )
            ),
            passenger_trips!inner(user_id, trip_name) 
          ''') // Added trip_name
          .eq('passenger_trips.user_id', userId)
          .eq('status', 'active');

      return (response as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('⚠️ Error fetching passenger subscriptions: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchDriverActiveSubscriptions(String userId) async {
    try {
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
              trip_name, 
              depart_lat, depart_lng,
              arrival_lat, arrival_lng
            ) 
          ''') // Added trip_name
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

  Future<bool> createTumpangRequest(Map<String, dynamic> requestPayload) async {
    try {
      await _supabase.from('tumpang_request').insert(requestPayload);
      return true;
    } catch (e) {
      print('⚠️ Error creating tumpang request: $e');
      return false;
    }
  }

  // --- NEW: Fetch existing requests so buttons stay disabled on reload ---
  Future<Set<String>> fetchRequestedDriverTripIds(String passengerTripId) async {
    try {
      final response = await _supabase
          .from('tumpang_request')
          .select('driver_trip_id')
          .eq('passenger_trip_id', passengerTripId)
          .or('status.eq.pending,status.eq.negotiating'); // Look for active requests

      return (response as List).map((row) => row['driver_trip_id'].toString()).toSet();
    } catch (e) {
      print('⚠️ Error fetching requested driver trips: $e');
      return {};
    }
  }
}