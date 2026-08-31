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

  Future<bool> submitException({
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
      print("Error in submitException: $e");
      return false;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}