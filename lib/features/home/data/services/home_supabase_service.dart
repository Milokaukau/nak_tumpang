import 'package:supabase_flutter/supabase_flutter.dart';

class HomeSupabaseService {
  final _supabase = Supabase.instance.client;

  /// Real signed-in user's profile (id/name/role), read from the current
  /// Supabase auth session — not a hardcoded mock ID. Returns null if
  /// nobody is signed in, or their `users` row doesn't exist yet.
  Future<Map<String, dynamic>?> fetchCurrentUserProfile() async {
    final authUser = _supabase.auth.currentUser;
    if (authUser == null) return null;

    try {
      final row = await _supabase
          .from('users')
          .select('name, role')
          .eq('id', authUser.id)
          .maybeSingle();

      if (row == null) return null;
      return {'id': authUser.id, ...row};
    } catch (e) {
      print('⚠️ Error fetching current user profile: $e');
      return null;
    }
  }

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