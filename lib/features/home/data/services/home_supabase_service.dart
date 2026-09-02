import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeSupabaseService {
  final _supabase = Supabase.instance.client;

  /// Runs [query] and normalizes both the success and failure paths so each
  /// public method below doesn't repeat the same try/catch/log/cast
  /// boilerplate.
  ///
  /// On error this logs via [debugPrint] (stripped from release builds)
  /// and returns an empty list, matching the previous behavior. Note this
  /// means a genuine network/server failure currently looks identical to a
  /// legitimate "no results" to the UI (e.g. "no unmatched trips" shows
  /// either way) -- worth returning a small Result/Either type instead if
  /// you want the panel to distinguish "empty" from "failed to load".
  Future<List<Map<String, dynamic>>> _runListQuery(
      String label,
      Future<dynamic> Function() query,
      ) async {
    try {
      final response = await query();
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('⚠️ Error in $label: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchPassengerTrips(String userId) {
    return _runListQuery(
      'fetchPassengerTrips',
          () => _supabase
          .from('passenger_trips')
      // NOTE: '*' pulls every column on passenger_trips and every user
      // column. Once the UI's exact field usage is confirmed, narrow
      // this the way fetchDriverTrips already does for `users`, to cut
      // payload size and avoid silently re-fetching new columns as the
      // schema grows.
          .select('*, users(*)')
          .eq('user_id', userId),
    );
  }

  Future<List<Map<String, dynamic>>> fetchDriverTrips() {
    return _runListQuery(
      'fetchDriverTrips',
          () => _supabase
          .from('driver_trips')
          .select('*, users(name, phone, avatar_url)'),
    );
  }

  // ==========================================
  // PASSENGER SUBSCRIPTIONS
  // ==========================================
  Future<List<Map<String, dynamic>>> fetchAllPassengerSubscriptions(String userId) {
    return _runListQuery(
      'fetchAllPassengerSubscriptions',
          () => _supabase
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
          .eq('status', 'active'),
    );
  }

  // ==========================================
  // DRIVER SUBSCRIPTIONS
  // ==========================================
  Future<List<Map<String, dynamic>>> fetchDriverActiveSubscriptions(String userId) {
    return _runListQuery(
      'fetchDriverActiveSubscriptions',
          () => _supabase
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
          .eq('status', 'active'),
    );
  }
}