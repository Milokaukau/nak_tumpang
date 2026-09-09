import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

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
                id, name, phone, avatar_url 
              )
            ),
            passenger_trips!inner(user_id),
            tumpang_trip_log ( id, trip_date ) 
          ''') // <-- Changed to trip_date
          .eq('passenger_trips.user_id', userId)
          .eq('status', 'active');

      final today = _formatDate(DateTime.now());

      return (response as List).map((e) {
        final sub = e as Map<String, dynamic>;
        final logs = sub['tumpang_trip_log'] as List<dynamic>? ?? [];

        sub['is_completed_today'] = logs.any((log) {
          final logDate = DateTime.tryParse(log['trip_date']?.toString() ?? '');
          if (logDate == null) return false;
          final now = DateTime.now();
          return logDate.year == now.year && logDate.month == now.month && logDate.day == now.day;
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
              depart_lat, depart_lng,
              arrival_lat, arrival_lng
            ),
            tumpang_trip_log ( id, trip_date ) 
          ''') // <-- Changed to trip_date
          .eq('driver_trips.user_id', userId)
          .eq('status', 'active');

      final today = _formatDate(DateTime.now()); // e.g. "2026-09-09"

      return (response as List).map((e) {
        final sub = e as Map<String, dynamic>;
        final logs = sub['tumpang_trip_log'] as List<dynamic>? ?? [];

        sub['is_completed_today'] = logs.any((log) {
          final logDate = DateTime.tryParse(log['trip_date']?.toString() ?? '');
          if (logDate == null) return false;
          final now = DateTime.now();
          return logDate.year == now.year && logDate.month == now.month && logDate.day == now.day;
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
          .or('status.eq.pending,status.eq.negotiating'); // Look for active requests

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

  Future<bool> completeTrip({
    required String subscriptionId,
    required String driverId,
    required String passengerId,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    // 1. GUARD: Prevent empty strings from crashing PostgreSQL
    if (subscriptionId.trim().isEmpty) {
      print('Error: subscriptionId is empty.');
      return false;
    }

    // 🔒 2. SECURITY GUARD: Only the assigned driver can complete the trip
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != driverId) {
      print('⚠️ Access denied: Only the driver can complete this trip.');
      return false;
    }

    try {
      final now = DateTime.now();
      final today = _formatDate(now);

      // 3. Check existing log
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

      // 4. Insert Trip Log
      await _supabase.from('tumpang_trip_log').insert({
        'id': tripLogId,
        'tumpang_subscription_id': subscriptionId,
        'trip_date': today,
        'completed_at': now.toIso8601String(),
        'distance_km': distanceKm,
        'status': 'completed',
      });

      // 5. Distribute Points Safely
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
          'expired_at': now.add(const Duration(days: 365)).toIso8601String(),
          'tumpang_trip_log_id': tripLogId,
        });

        await _supabase.from('points_ledger').insert({
          'id': 'pl_${now.millisecondsSinceEpoch}_$userId',
          'user_id': userId,
          'change_amount': points,
          'reason': 'trip_completed',
          'reference_id': tripLogId,
          'description': 'Earned from completed trip (${distanceKm.toStringAsFixed(1)}km)',
          'created_at': now.toIso8601String(),
        });
      }

      return true;
    } on PostgrestException catch (e) {
      print('❌ Supabase Error in completeTrip: ${e.message} (code: ${e.code})');
      return false;
    } catch (e) {
      print('❌ General Error in completeTrip: $e');
      return false;
    }
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    // Haversine formula, returns meters
    const R = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double deg) => deg * (pi / 180);

  int _calculatePoints(double distanceKm) {
    const basePoints = 5;
    const bonusCap = 10;
    final bonus = (distanceKm / 2).floor().clamp(0, bonusCap);
    return basePoints + bonus;
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}