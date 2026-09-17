import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';
import 'package:nak_tumpang/features/home/data/services/home_local_service.dart';

class SubscriptionLocalService {
  final LocalDbService _dbService = LocalDbService.instance;

  Future<void> cacheExceptions({
    required String subscriptionId,
    required List<Map<String, dynamic>> exceptions,
  }) async {
    final db = await _dbService.database;

    await db.transaction((txn) async {
      final batch = txn.batch();

      batch.delete(
        'tumpang_exception',
        where: 'tumpang_subscription_id = ?',
        whereArgs: [subscriptionId],
      );

      for (final ex in exceptions) {
        batch.insert(
          'tumpang_exception',
          {
            'id': ex['id'],
            'tumpang_subscription_id': subscriptionId,
            'initiated_by': ex['initiated_by'],
            'initiated_by_role': ex['initiated_by_role'],
            'start_date': ex['start_date'],
            'end_date': ex['end_date'],
            'reason': ex['reason'],
            'status': ex['status'] ?? 'active',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getCachedExceptions(String subscriptionId) async {
    final db = await _dbService.database;
    return db.query(
      'tumpang_exception',
      where: 'tumpang_subscription_id = ? AND status = ?',
      whereArgs: [subscriptionId, 'active'],
      orderBy: 'start_date DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllCachedExceptions(String subscriptionId) async {
    final db = await _dbService.database;
    return db.query(
      'tumpang_exception',
      where: 'tumpang_subscription_id = ?',
      whereArgs: [subscriptionId],
      orderBy: 'start_date DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getCachedSubscriptionsForList(String userId, String role) async {
    final isForPassenger = role == 'passenger';
    final rawSubs = await HomeLocalService().getCachedSubscriptions(userId, isForPassenger: isForPassenger);

    final results = <Map<String, dynamic>>[];
    for (final sub in rawSubs) {
      final mapped = Map<String, dynamic>.from(sub);

      final driverTrip = (mapped['driver_trips'] as Map<String, dynamic>?) ?? {};
      final passengerTrip = (mapped['passenger_trips'] as Map<String, dynamic>?) ?? {};
      final partnerUsers = (isForPassenger ? driverTrip['users'] : passengerTrip['users']) as Map<String, dynamic>?;

      mapped['name'] = partnerUsers?['name'] ?? 'User';
      mapped['phone'] = partnerUsers?['phone'] ?? 'N/A';
      mapped['imageUrl'] = partnerUsers?['avatar_url'];

      final activeExceptions = await getCachedExceptions(mapped['id']?.toString() ?? '');
      mapped['has_active_exception'] = activeExceptions.isNotEmpty;

      results.add(mapped);
    }
    return results;
  }
}