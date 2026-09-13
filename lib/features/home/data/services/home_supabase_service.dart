import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

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

  Future<List<Map<String, dynamic>>> fetchAllPassengerSubscriptions(String userId) async {
    try {
      final response = await _supabase
          .from('tumpang_subscription')
          .select('''
            *,
            driver_trips (
              users (
                id, name, phone, avatar_url 
              )
            ),
            passenger_trips!inner(user_id, trip_name),
            tumpang_trip_log ( id, trip_date ) 
          ''')
          .eq('passenger_trips.user_id', userId)
          .ilike('status', 'active'); // <-- FIX: Case-insensitive 'active'

      final rawList = (response as List).map((e) => e as Map<String, dynamic>).toList();
      final List<Map<String, dynamic>> validActiveList = [];

      final now = DateTime.now();
      final todayDateOnly = DateTime(now.year, now.month, now.day);

      for (var sub in rawList) {
        // <-- FIX: Case-insensitive check in dart
        if (sub['status']?.toString().toLowerCase() == 'active' && sub['subscription_end_date'] != null) {
          final endDate = DateTime.tryParse(sub['subscription_end_date']);

          if (endDate != null && endDate.isBefore(todayDateOnly)) {
            await _checkAndAutoExpire(sub['id'], sub['subscription_end_date']);
            continue;
          }
        }
        validActiveList.add(sub);
      }

      return validActiveList.map((sub) {
        final logs = sub['tumpang_trip_log'] as List<dynamic>? ?? [];

        sub['is_completed_today'] = logs.any((log) {
          final logDate = DateTime.tryParse(log['trip_date']?.toString() ?? '');
          if (logDate == null) return false;
          final current = DateTime.now();
          return logDate.year == current.year && logDate.month == current.month && logDate.day == current.day;
        });

        return sub;
      }).toList();
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
                id, name, phone, avatar_url 
              )
            ),
            driver_trips!inner(
              user_id,
              trip_name, 
              depart_lat, depart_lng,
              arrival_lat, arrival_lng
            ),
            tumpang_trip_log ( id, trip_date ) 
          ''')
          .eq('driver_trips.user_id', userId)
          .ilike('status', 'active'); // <-- FIX: Case-insensitive 'active'

      final rawList = (response as List).map((e) => e as Map<String, dynamic>).toList();
      final List<Map<String, dynamic>> validActiveList = [];

      final now = DateTime.now();
      final todayDateOnly = DateTime(now.year, now.month, now.day);

      for (var sub in rawList) {
        // <-- FIX: Case-insensitive check in dart
        if (sub['status']?.toString().toLowerCase() == 'active' && sub['subscription_end_date'] != null) {
          final endDate = DateTime.tryParse(sub['subscription_end_date']);

          if (endDate != null && endDate.isBefore(todayDateOnly)) {
            await _checkAndAutoExpire(sub['id'], sub['subscription_end_date']);
            continue;
          }
        }
        validActiveList.add(sub);
      }

      return validActiveList.map((sub) {
        final logs = sub['tumpang_trip_log'] as List<dynamic>? ?? [];

        sub['is_completed_today'] = logs.any((log) {
          final logDate = DateTime.tryParse(log['trip_date']?.toString() ?? '');
          if (logDate == null) return false;
          final current = DateTime.now();
          return logDate.year == current.year && logDate.month == current.month && logDate.day == current.day;
        });

        return sub;
      }).toList();
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

  Future<Set<String>> fetchRequestedDriverTripIds(String passengerTripId) async {
    try {
      final response = await _supabase
          .from('tumpang_request')
          .select('driver_trip_id')
          .eq('passenger_trip_id', passengerTripId)
          .or('status.eq.pending,status.eq.negotiating');

      return (response as List).map((row) => row['driver_trip_id'].toString()).toSet();
    } catch (e) {
      print('⚠️ Error fetching requested driver trips: $e');
      return {};
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
        'status': 'active', // Safe to insert as lowercase
      });
      return true;
    } catch (e) {
      print("Error in createException: $e");
      return false;
    }
  }

  Future<void> _checkAndAutoExpire(String subscriptionId, String endDateStr) async {
    final endDate = DateTime.tryParse(endDateStr);
    if (endDate == null) return;
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    if (endDate.isBefore(todayDateOnly)) {
      await _supabase.from('tumpang_subscription').update({
        'status': 'inactive',
        'ended_by': 'natural',
        'ended_at': DateTime.now().toIso8601String(),
        'deposit_refunded': true,
      }).eq('id', subscriptionId);
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

  Future<bool> completeTrip({
    required String subscriptionId,
    required String driverId,
    required String passengerId,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    if (subscriptionId.trim().isEmpty) {
      print('Error: subscriptionId is empty.');
      return false;
    }

    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != driverId) {
      print('⚠️ Access denied: Only the driver can complete this trip.');
      return false;
    }

    try {
      final now = DateTime.now();
      final today = _formatDate(now);

      final existing = await _supabase
          .from('tumpang_trip_log')
          .select('id')
          .eq('tumpang_subscription_id', subscriptionId)
          .eq('trip_date', today);

      if ((existing as List).isNotEmpty) {
        print('⚠️ Blocked: Trip already completed today.');
        return false;
      }

      final distanceKm = _calculateDistance(pickupLat, pickupLng, dropoffLat, dropoffLng) / 1000;
      final tripLogId = 'log_${now.millisecondsSinceEpoch}';

      await _supabase.from('tumpang_trip_log').insert({
        'id': tripLogId,
        'tumpang_subscription_id': subscriptionId,
        'trip_date': today,
        'completed_at': now.toIso8601String(),
        'distance_km': distanceKm,
        'status': 'completed',
      });

      final points = _calculatePoints(distanceKm);
      final uniqueUserIds = {driverId, passengerId}.where((id) => id.trim().isNotEmpty).toSet();

      for (final userId in uniqueUserIds) {
        final rewardId = 'rp_${now.millisecondsSinceEpoch}_$userId';

        await _supabase.from('reward_points').insert({
          'id': rewardId,
          'user_id': userId,
          'obtained_points': points,
          'avai_points': points,
          'obtained_at': now.toIso8601String(),
          'expired_at': now.add(const Duration(days: 90)).toIso8601String(),
          'tumpang_trip_log_id': tripLogId,
        });

        await _supabase.from('points_ledger').insert({
          'id': 'pl_${now.millisecondsSinceEpoch}_$userId',
          'user_id': userId,
          'change_amount': points,
          'reason': 'trip_completed',
          'reference_id': rewardId,
          'description': 'Earned from completed trip (${distanceKm.toStringAsFixed(1)}km)',
          'created_at': now.toIso8601String(),
        });
      }
      return true;
    } catch (e) {
      print('⚠️ Error in completeTrip: $e');
      return false;
    }
  }

  String _formatDate(DateTime date) => "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 + cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)) * 1000;
  }

  int _calculatePoints(double distanceKm) {
    if (distanceKm < 5) return 5;
    if (distanceKm < 15) return 10;
    if (distanceKm < 30) return 20;
    return 30;
  }
}