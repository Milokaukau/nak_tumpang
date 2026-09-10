import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class HomeLocalService {
  final LocalDbService _dbService = LocalDbService.instance;

  Future<String?> getUserRole(String userId) async {
    final db = await _dbService.database;
    final results = await db.query('users', columns: ['role'], where: 'id = ?', whereArgs: [userId]);
    if (results.isNotEmpty) return results.first['role'] as String;
    return null;
  }

  // --- 1. Cache Trips ---
  Future<void> cacheUserTrips(
      List<Map<String, dynamic>> trips, {
        required bool isForPassenger,
        required String currentUserId,
      }) async {
    final db = await _dbService.database;
    final batch = db.batch();
    final table = isForPassenger ? 'passenger_trips' : 'driver_trips';

    // Clear old cache to prevent zombie data
    batch.delete(table, where: 'user_id = ?', whereArgs: [currentUserId]);

    batch.insert('users', {
      'id': currentUserId,
      'name': 'User',
      'email': '$currentUserId@placeholder.com',
      'phone': 'N/A',
      'role': isForPassenger ? 'passenger' : 'driver',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    for (final t in trips) {
      batch.insert(table, {
        'id': t['id'],
        'user_id': t['user_id'] ?? currentUserId,
        'trip_name': t['trip_name'] ?? 'My Trip',
        'depart_time': t['depart_time'] ?? '00:00:00',
        'arrival_time': t['arrival_time'] ?? '00:00:00',
        'desired_pickup_time': t['desired_pickup_time'] ?? '00:00:00',
        'desired_dropoff_time': t['desired_dropoff_time'] ?? '00:00:00',
        'depart_lat': t['depart_lat'] ?? 0.0,
        'depart_lng': t['depart_lng'] ?? 0.0,
        'depart_name': t['depart_name'] ?? '',
        'arrival_lat': t['arrival_lat'] ?? 0.0,
        'arrival_lng': t['arrival_lng'] ?? 0.0,
        'arrival_name': t['arrival_name'] ?? '',
        'pickup_lat': t['pickup_lat'] ?? 0.0,
        'pickup_lng': t['pickup_lng'] ?? 0.0,
        'pickup_name': t['pickup_name'] ?? '',
        'dropoff_lat': t['dropoff_lat'] ?? 0.0,
        'dropoff_lng': t['dropoff_lng'] ?? 0.0,
        'dropoff_name': t['dropoff_name'] ?? '',
        // Point 1 Fix: Add recurrence flags
        'active_monday': t['active_monday'] == true ? 1 : 0,
        'active_tuesday': t['active_tuesday'] == true ? 1 : 0,
        'active_wednesday': t['active_wednesday'] == true ? 1 : 0,
        'active_thursday': t['active_thursday'] == true ? 1 : 0,
        'active_friday': t['active_friday'] == true ? 1 : 0,
        'active_saturday': t['active_saturday'] == true ? 1 : 0,
        'active_sunday': t['active_sunday'] == true ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // --- 2. Cache Subscriptions ---
  Future<void> cacheActiveSubscriptions(
      List<Map<String, dynamic>> rawSubs, {
        required bool isForPassenger,
        required String currentUserId,
      }) async {
    final db = await _dbService.database;
    final batch = db.batch();

    batch.insert('users', {
      'id': currentUserId,
      'name': 'Me',
      'email': '$currentUserId@placeholder.com',
      'phone': 'N/A',
      'role': isForPassenger ? 'passenger' : 'driver',
      'status': 'active',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    for (final sub in rawSubs) {
      final tripKey = isForPassenger ? 'driver_trips' : 'passenger_trips';
      final myTripKey = isForPassenger ? 'passenger_trips' : 'driver_trips';

      final partnerTrip = (sub[tripKey] as Map<String, dynamic>?) ?? {};
      final myTrip = (sub[myTripKey] as Map<String, dynamic>?) ?? {};
      final partnerUser = (partnerTrip['users'] as Map<String, dynamic>?) ?? {};

      final partnerUserId = partnerTrip['user_id'] ?? partnerUser['id'] ?? 'unknown_partner_${sub['id']}';
      final myTripUserId = myTrip['user_id'] ?? currentUserId;

      // Point 2 Fix: Changed to ignore to prevent CASCADE delete
      batch.insert('users', {
        'id': partnerUserId,
        'name': partnerUser['name'] ?? 'User',
        'email': partnerUser['email'] ?? '$partnerUserId@placeholder.com',
        'phone': partnerUser['phone'] ?? 'N/A',
        'role': isForPassenger ? 'driver' : 'passenger',
        'avatar_url': partnerUser['avatar_url'],
        'status': 'active',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      // Update mutable user fields directly instead of REPLACE
      batch.update('users', {
        'name': partnerUser['name'] ?? 'User',
        'phone': partnerUser['phone'] ?? 'N/A',
        'avatar_url': partnerUser['avatar_url'],
      }, where: 'id = ?', whereArgs: [partnerUserId]);

      final dTripUserId = isForPassenger ? partnerUserId : myTripUserId;
      if (sub['driver_trip_id'] != null) {
        batch.insert('driver_trips', {
          'id': sub['driver_trip_id'],
          'user_id': dTripUserId,
          'trip_name': partnerTrip['trip_name'] ?? myTrip['trip_name'] ?? 'Driver Trip',
          'depart_time': partnerTrip['depart_time'] ?? myTrip['depart_time'] ?? '00:00:00',
          'arrival_time': partnerTrip['arrival_time'] ?? myTrip['arrival_time'] ?? '00:00:00',
          'depart_lat': partnerTrip['depart_lat'] ?? myTrip['depart_lat'] ?? 0.0,
          'depart_lng': partnerTrip['depart_lng'] ?? myTrip['depart_lng'] ?? 0.0,
          'depart_name': partnerTrip['depart_name'] ?? myTrip['depart_name'] ?? '',
          'arrival_lat': partnerTrip['arrival_lat'] ?? myTrip['arrival_lat'] ?? 0.0,
          'arrival_lng': partnerTrip['arrival_lng'] ?? myTrip['arrival_lng'] ?? 0.0,
          'arrival_name': partnerTrip['arrival_name'] ?? myTrip['arrival_name'] ?? '',
        }, conflictAlgorithm: ConflictAlgorithm.ignore); // Point 2 Fix
      }

      final pTripUserId = isForPassenger ? myTripUserId : partnerUserId;
      if (sub['passenger_trip_id'] != null) {
        batch.insert('passenger_trips', {
          'id': sub['passenger_trip_id'],
          'user_id': pTripUserId,
          'trip_name': partnerTrip['trip_name'] ?? myTrip['trip_name'] ?? 'Passenger Trip',
          'desired_pickup_time': partnerTrip['desired_pickup_time'] ?? myTrip['desired_pickup_time'] ?? '00:00:00',
          'desired_dropoff_time': partnerTrip['desired_dropoff_time'] ?? myTrip['desired_dropoff_time'] ?? '00:00:00',
          'pickup_lat': partnerTrip['pickup_lat'] ?? myTrip['pickup_lat'] ?? 0.0,
          'pickup_lng': partnerTrip['pickup_lng'] ?? myTrip['pickup_lng'] ?? 0.0,
          'pickup_name': partnerTrip['pickup_name'] ?? myTrip['pickup_name'] ?? '',
          'dropoff_lat': partnerTrip['dropoff_lat'] ?? myTrip['dropoff_lat'] ?? 0.0,
          'dropoff_lng': partnerTrip['dropoff_lng'] ?? myTrip['dropoff_lng'] ?? 0.0,
          'dropoff_name': partnerTrip['dropoff_name'] ?? myTrip['dropoff_name'] ?? '',
        }, conflictAlgorithm: ConflictAlgorithm.ignore); // Point 2 Fix
      }

      batch.insert('tumpang_subscription', {
        'id': sub['id'],
        'passenger_trip_id': sub['passenger_trip_id'],
        'driver_trip_id': sub['driver_trip_id'],
        'pickup_lat': sub['pickup_lat'],
        'pickup_lng': sub['pickup_lng'],
        'pickup_location': sub['pickup_location'],
        'dropoff_lat': sub['dropoff_lat'],
        'dropoff_lng': sub['dropoff_lng'],
        'dropoff_location': sub['dropoff_location'],
        'pickup_time': sub['pickup_time'],
        'fee': sub['fee'] ?? 0.0,
        'deposit': sub['deposit'] ?? 0.0,
        'subscription_start_date': sub['subscription_start_date'] ?? '',
        'subscription_end_date': sub['subscription_end_date'] ?? '',
        'status': sub['status'] ?? 'active',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  // --- 3. Get Trips Offline ---
  Future<List<Map<String, dynamic>>> getCachedUserTrips(String userId, {required bool isForPassenger}) async {
    final db = await _dbService.database;
    final table = isForPassenger ? 'passenger_trips' : 'driver_trips';
    return await db.query(table, where: 'user_id = ?', whereArgs: [userId]);
  }

  // --- 4. Get Subscriptions Offline ---
  Future<List<Map<String, dynamic>>> getCachedSubscriptions(
      String userId, {
        required bool isForPassenger,
      }) async {
    final db = await _dbService.database;

    final filterColumn = isForPassenger ? 'pt.user_id' : 'dt.user_id';

    final results = await db.rawQuery('''
      SELECT 
        s.*,
        pt.user_id AS pt_user_id, pt.trip_name AS pt_trip_name,
        dt.user_id AS dt_user_id, dt.trip_name AS dt_trip_name,
        dt.depart_lat, dt.depart_lng, dt.arrival_lat, dt.arrival_lng,
        u.name AS u_name, u.phone AS u_phone, u.avatar_url AS u_avatar_url
      FROM tumpang_subscription s
      INNER JOIN passenger_trips pt ON s.passenger_trip_id = pt.id
      LEFT JOIN driver_trips dt ON s.driver_trip_id = dt.id
      LEFT JOIN users u ON ${isForPassenger ? 'dt.user_id' : 'pt.user_id'} = u.id
      WHERE $filterColumn = ? AND s.status = 'active'
    ''', [userId]);

    return results.map((row) {
      return {
        'id': row['id'],
        'passenger_trip_id': row['passenger_trip_id'],
        'driver_trip_id': row['driver_trip_id'],
        'status': row['status'],
        'pickup_time': row['pickup_time'],
        'pickup_location': row['pickup_location'],
        'dropoff_location': row['dropoff_location'],
        'pickup_lat': row['pickup_lat'],
        'pickup_lng': row['pickup_lng'],
        'dropoff_lat': row['dropoff_lat'],
        'dropoff_lng': row['dropoff_lng'],
        'fee': row['fee'],
        'deposit': row['deposit'],
        'subscription_start_date': row['subscription_start_date'],
        'subscription_end_date': row['subscription_end_date'],
        'passenger_trips': {
          'user_id': row['pt_user_id'],
          'trip_name': row['pt_trip_name'],
          if (!isForPassenger)
            'users': {
              'name': row['u_name'],
              'phone': row['u_phone'],
              'avatar_url': row['u_avatar_url'],
            },
        },
        'driver_trips': {
          'user_id': row['dt_user_id'],
          'trip_name': row['dt_trip_name'],
          'depart_lat': row['depart_lat'],
          'depart_lng': row['depart_lng'],
          'arrival_lat': row['arrival_lat'],
          'arrival_lng': row['arrival_lng'],
          if (isForPassenger)
            'users': {
              'name': row['u_name'],
              'phone': row['u_phone'],
              'avatar_url': row['u_avatar_url'],
            },
        },
      };
    }).toList();
  }
}