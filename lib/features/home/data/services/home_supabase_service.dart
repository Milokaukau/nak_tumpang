import 'package:supabase_flutter/supabase_flutter.dart';

class HomeSupabaseService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> fetchPassengerTrip(String userId) async {
    try {
      final trip = await _supabase
          .from('passenger_trips')
          .select('*, users(*)')
          .eq('user_id', userId)
          .maybeSingle();

      return trip;
    } catch (e) {
      print("Error in fetchPassengerTrip: $e");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchDriverTrips() async {
    try {
      final response = await _supabase
          .from('driver_trips')
          .select('*, users(name)');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error in fetchDriverTrips: $e");
      return [];
    }
  }
}