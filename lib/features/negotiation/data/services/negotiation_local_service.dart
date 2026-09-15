import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class NegotiationLocalService {
  // Use the singleton instance
  final LocalDbService _dbService = LocalDbService.instance;

  // INSERT OR REPLACE (Upsert) to cache requests from Supabase
  Future<void> cacheTumpangRequests(List<Map<String, dynamic>> requests) async {
    final db = await _dbService.database;

    // Temporarily bypass strict foreign key rules to allow partial caching.
    // Everything between here and the PRAGMA ON below is wrapped in
    // try/finally: this connection is shared, so if batch.commit() throws
    // (e.g. a genuinely malformed row) and we don't restore the PRAGMA,
    // foreign_keys stays OFF for every later write on this connection —
    // silently letting unrelated writes create invalid relationships.
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
      // Restore the strict rules to respect the team lead's configuration —
      // runs even if batch.commit() above threw.
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  // SELECT for offline viewing (Pending and Complete only)
  // NOTE ON ACCOUNT SCOPING: this table has no owner/user-id column to
  // filter by, so this cache is only ever safe to hold ONE account's data
  // at a time. NegotiationViewModel is responsible for calling
  // [clearRequestsCache] on logout and on switching to a different
  // account (see its auth-state listener) so a second user on the same
  // device can never read a previous user's cached negotiation terms.
  Future<List<Map<String, dynamic>>> getOfflineRequests(String status) async {
    final db = await _dbService.database;

    final result = await db.query(
      'tumpang_request',
      where: 'status = ?',
      whereArgs: [status], // e.g., 'pending' or 'completed'
    );

    return result.map((row) => _mapIntegersToBooleans(row)).toList();
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
    // Add all your boolean field names here
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