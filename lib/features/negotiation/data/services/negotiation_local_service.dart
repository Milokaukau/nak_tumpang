import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class NegotiationLocalService {
  // Use the singleton instance
  final LocalDbService _dbService = LocalDbService.instance;

  // INSERT OR REPLACE (Upsert) to cache requests from Supabase
  Future<void> cacheTumpangRequests(List<Map<String, dynamic>> requests) async {
    final db = await _dbService.database;

    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      final batch = db.batch();
      for (var request in requests) {
        // Ensure booleans are converted to INTEGER (0 or 1) for SQLite
        final mappedRequest = _mapBooleansToIntegers(request);
        batch.insert(
          'tumpang_request',
          mappedRequest,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  // SELECT for offline viewing (Pending and Complete only)
  Future<List<Map<String, dynamic>>> getOfflineRequests(String status) async {
    // FIX: Using readOnlyDatabase bypasses database locks from background writes,
    // instantly fixing the "long load" freeze.
    final db = await _dbService.readOnlyDatabase;

    final result = await db.query(
      'tumpang_request',
      where: 'status = ?',
      whereArgs: [status],
    );

    return result.map((row) => _mapIntegersToBooleans(row)).toList();
  }

  // NEW FIX: Allows buttons/notifications to fetch a specific request instantly offline
  // without relying on memory caches that might be frozen.
  Future<Map<String, dynamic>?> getOfflineRequestById(String id) async {
    final db = await _dbService.readOnlyDatabase;
    final result = await db.query(
      'tumpang_request',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isNotEmpty) {
      return _mapIntegersToBooleans(result.first);
    }
    return null;
  }

  // DELETE to clear cache upon logout
  Future<void> clearRequestsCache() async {
    final db = await _dbService.database;
    await db.delete('tumpang_request');
  }

  // --- Helpers for SQLite Boolean Mapping ---
  Map<String, dynamic> _mapBooleansToIntegers(Map<String, dynamic> data) {
    final result = Map<String, dynamic>.from(data);
    result.forEach((key, value) {
      if (value is bool) {
        result[key] = value ? 1 : 0;
      }
    });
    return result;
  }

  Map<String, dynamic> _mapIntegersToBooleans(Map<String, dynamic> data) {
    final result = Map<String, dynamic>.from(data);
    final boolFields = [
      'pickup_is_accepted', 'dropoff_is_accepted', 'pickup_time_is_accepted',
      'fee_is_accepted', 'sub_start_is_accepted', 'sub_end_is_accepted', 'is_extension'
    ];
    for (var field in boolFields) {
      if (result.containsKey(field) && result[field] != null) {
        result[field] = result[field] == 1;
      }
    }
    return result;
  }
}