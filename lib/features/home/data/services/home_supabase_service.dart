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

  Future<bool> createException({
    required String tumpangSubscriptionId,
    required String initiatedBy,
    required String initiatedByRole,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    try {
      await _supabase.from('tumpang_exception').insert({
        'tumpang_subscription_id': tumpangSubscriptionId,
        'initiated_by': initiatedBy,
        'initiated_by_role': initiatedByRole,
        'start_date': _formatDate(startDate),
        'end_date': _formatDate(endDate),
        'reason': reason,
        'status': 'active',
      });
      return true;
    } catch (e) {
      print("Error in createException: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchUserById(String userId) async {
    try {
      final response = await _supabase.from('users').select().eq('id', userId).maybeSingle();
      return response;
    } catch (e) {
      print('Error in fetchUserById: $e');
      return null;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}