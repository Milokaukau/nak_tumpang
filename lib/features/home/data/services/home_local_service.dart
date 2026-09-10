import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class HomeLocalService {
  final LocalDbService _dbService = LocalDbService.instance;

  // --- 1. Cache Trips ---
  Future<void> cacheUserTrips(
      List<Map<String, dynamic>> trips, {
        required bool isForPassenger,
        required String currentUserId,
      }) async {
    final db = await _dbService.database;
    final batch = db.batch();
    final table = isForPassenger ? 'passenger_trips' : 'driver_trips';

    // Added a placeholder email to satisfy the NOT NULL UNIQUE constraint
    batch.insert('users', {
      'id': currentUserId,
      'name': 'User',
      'email': '$currentUserId@placeholder.com',
      'phone': 'N/A',
      'role': isForPassenger ? 'passenger' : 'driver',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    for (final t in trips) {
      if (isForPassenger) {
        batch.insert(table, {
          'id': t['id'],
          'user_id': t['user_id'] ?? currentUserId,
          'trip_name': t['trip_name'] ?? 'My Trip',
          'desired_pickup_time': t['desired_pickup_time'] ?? '00:00:00',
          'desired_dropoff_time': t['desired_dropoff_time'] ?? '00:00:00',
          'pickup_lat': t['pickup_lat'] ?? 0.0,
          'pickup_lng': t['pickup_lng'] ?? 0.0,
          'pickup_name': t['pickup_name'] ?? '',
          'dropoff_lat': t['dropoff_lat'] ?? 0.0,
          'dropoff_lng': t['dropoff_lng'] ?? 0.0,
          'dropoff_name': t['dropoff_name'] ?? '',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        batch.insert(table, {
          'id': t['id'],
          'user_id': t['user_id'] ?? currentUserId,
          'trip_name': t['trip_name'] ?? 'My Trip',
          'depart_time': t['depart_time'] ?? '00:00:00',
          'arrival_time': t['arrival_time'] ?? '00:00:00',
          'depart_lat': t['depart_lat'] ?? 0.0,
          'depart_lng': t['depart_lng'] ?? 0.0,
          'depart_name': t['depart_name'] ?? '',
          'arrival_lat': t['arrival_lat'] ?? 0.0,
          'arrival_lng': t['arrival_lng'] ?? 0.0,
          'arrival_name': t['arrival_name'] ?? '',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
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

    // Added a placeholder email to satisfy the NOT NULL UNIQUE constraint
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

      // Fallback email for partner user
      batch.insert('users', {
        'id': partnerUserId,
        'name': partnerUser['name'] ?? 'User',
        'email': partnerUser['email'] ?? '$partnerUserId@placeholder.com',
        'phone': partnerUser['phone'] ?? 'N/A',
        'role': isForPassenger ? 'driver' : 'passenger',
        'avatar_url': partnerUser['avatar_url'],
        'status': 'active',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Insert Driver Trip
      final dTrip = isForPassenger ? partnerTrip : myTrip;
      final dTripUserId = isForPassenger ? partnerUserId : myTripUserId;

      if (sub['driver_trip_id'] != null) {
        batch.insert('driver_trips', {
          'id': sub['driver_trip_id'],
          'user_id': dTripUserId,
          'trip_name': dTrip['trip_name'] ?? 'Driver Trip',
          'depart_time': dTrip['depart_time'] ?? '00:00:00',
          'arrival_time': dTrip['arrival_time'] ?? '00:00:00',
          'depart_lat': dTrip['depart_lat'] ?? 0.0,
          'depart_lng': dTrip['depart_lng'] ?? 0.0,
          'depart_name': dTrip['depart_name'] ?? '',
          'arrival_lat': dTrip['arrival_lat'] ?? 0.0,
          'arrival_lng': dTrip['arrival_lng'] ?? 0.0,
          'arrival_name': dTrip['arrival_name'] ?? '',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Insert Passenger Trip
      final pTrip = isForPassenger ? myTrip : partnerTrip;
      final pTripUserId = isForPassenger ? myTripUserId : partnerUserId;

      if (sub['passenger_trip_id'] != null) {
        batch.insert('passenger_trips', {
          'id': sub['passenger_trip_id'],
          'user_id': pTripUserId,
          'trip_name': pTrip['trip_name'] ?? 'Passenger Trip',
          'desired_pickup_time': pTrip['desired_pickup_time'] ?? '00:00:00',
          'desired_dropoff_time': pTrip['desired_dropoff_time'] ?? '00:00:00',
          'pickup_lat': pTrip['pickup_lat'] ?? 0.0,
          'pickup_lng': pTrip['pickup_lng'] ?? 0.0,
          'pickup_name': pTrip['pickup_name'] ?? '',
          'dropoff_lat': pTrip['dropoff_lat'] ?? 0.0,
          'dropoff_lng': pTrip['dropoff_lng'] ?? 0.0,
          'dropoff_name': pTrip['dropoff_name'] ?? '',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Insert Subscription
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