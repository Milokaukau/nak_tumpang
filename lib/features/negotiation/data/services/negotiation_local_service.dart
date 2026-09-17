import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class NegotiationLocalService {
  // Use the singleton instance
  final LocalDbService _dbService = LocalDbService.instance;

  // FIX: Make ownerId optional `[String? ownerId]` to prevent breaking team members' code
  //
  // SAFETY NET: `owner_id` scoping requires the local `tumpang_request`
  // table's schema to already include an `owner_id` column. If a device is
  // running on an older schema that hasn't been migrated yet, writing that
  // column would throw ("no such column: owner_id") and - since this call is
  // wrapped in a try/catch by callers - offline caching would silently stop
  // working entirely for that device. To avoid that failure mode, if the
  // owner-scoped insert fails with a missing-column error, we transparently
  // retry once without owner_id so caching keeps working; account isolation
  // then falls back to the existing clearRequestsCache()-on-account-switch
  // behavior instead of per-row scoping.
  Future<void> cacheTumpangRequests(List<Map<String, dynamic>> requests, [String? ownerId]) async {
    final db = await _dbService.database;

    Future<void> insertBatch({required bool includeOwnerId}) async {
      final batch = db.batch();
      for (var request in requests) {
        final mappedRequest = _mapBooleansToIntegers(request);
        if (includeOwnerId && ownerId != null) {
          mappedRequest['owner_id'] = ownerId;
        }
        batch.insert('tumpang_request', mappedRequest, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }

    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      try {
        await insertBatch(includeOwnerId: true);
      } on DatabaseException catch (e) {
        if (ownerId != null && _isMissingColumnError(e)) {
          await insertBatch(includeOwnerId: false);
        } else {
          rethrow;
        }
      }
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  // FIX: Make ownerId optional `[String? ownerId]` to prevent breaking team members' code
  Future<List<Map<String, dynamic>>> getOfflineRequests(String status, [String? ownerId]) async {
    final db = await _dbService.readOnlyDatabase;
    List<Map<String, Object?>> result;

    if (ownerId != null) {
      try {
        result = await db.query(
          'tumpang_request',
          where: 'status = ? AND owner_id = ?',
          whereArgs: [status, ownerId],
        );
      } on DatabaseException catch (e) {
        // Schema hasn't been migrated to include owner_id yet - fall back
        // rather than surfacing an empty/broken offline list.
        if (!_isMissingColumnError(e)) rethrow;
        result = await db.query(
          'tumpang_request',
          where: 'status = ?',
          whereArgs: [status],
        );
      }
    } else {
      // Legacy fallback for team members who haven't updated their modules yet
      result = await db.query(
        'tumpang_request',
        where: 'status = ?',
        whereArgs: [status],
      );
    }
    return result.map((row) => _mapIntegersToBooleans(row)).toList();
  }

  // FIX: Make ownerId optional `[String? ownerId]` to prevent breaking team members' code
  Future<Map<String, dynamic>?> getOfflineRequestById(String id, [String? ownerId]) async {
    final db = await _dbService.readOnlyDatabase;
    List<Map<String, Object?>> result;

    if (ownerId != null) {
      try {
        result = await db.query(
          'tumpang_request',
          where: 'id = ? AND owner_id = ?',
          whereArgs: [id, ownerId],
        );
      } on DatabaseException catch (e) {
        // Schema hasn't been migrated to include owner_id yet - fall back
        // rather than failing the lookup outright.
        if (!_isMissingColumnError(e)) rethrow;
        result = await db.query(
          'tumpang_request',
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    } else {
      // Legacy fallback for team members who haven't updated their modules yet
      result = await db.query(
        'tumpang_request',
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    if (result.isNotEmpty) return _mapIntegersToBooleans(result.first);
    return null;
  }

  /// True if [e] is sqlite's "no such column" error, i.e. the local schema
  /// hasn't been migrated to include a column this code expects yet.
  bool _isMissingColumnError(DatabaseException e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('no such column') || msg.contains('has no column named');
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