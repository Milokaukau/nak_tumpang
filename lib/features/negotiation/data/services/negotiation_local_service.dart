import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class NegotiationLocalService {
  // Use the singleton instance
  final LocalDbService _dbService = LocalDbService.instance;

  // Cached in-memory once we've confirmed (or added) the owner_id column on
  // this process's database connection, so we don't re-issue the ALTER
  // TABLE / probe on every call.
  bool _ownerIdColumnReady = false;

  /// Ensures `tumpang_request.owner_id` exists, adding it if this device's
  /// local schema predates the column. This makes owner_id scoping work
  /// unconditionally — independent of LocalDbService's own migration
  /// version — so callers never need to silently fall back to an unscoped
  /// query (which would defeat the point of the scoping: if the cache
  /// somehow isn't cleared on an account switch, an unscoped fallback could
  /// let one account see another's cached negotiation data offline).
  /// ALTER TABLE ... ADD COLUMN is idempotent-safe here: if the column
  /// already exists (normal case, or a race with a concurrent call) SQLite
  /// throws "duplicate column name", which we treat as success.
  Future<void> _ensureOwnerIdColumn() async {
    if (_ownerIdColumnReady) return;
    final db = await _dbService.database;
    try {
      await db.execute('ALTER TABLE tumpang_request ADD COLUMN owner_id TEXT');
    } on DatabaseException catch (e) {
      if (!_isDuplicateColumnError(e)) rethrow;
    }
    _ownerIdColumnReady = true;
  }

  bool _isDuplicateColumnError(DatabaseException e) {
    return e.toString().toLowerCase().contains('duplicate column name');
  }

  Future<void> cacheTumpangRequests(List<Map<String, dynamic>> requests, [String? ownerId]) async {
    await _ensureOwnerIdColumn();
    final db = await _dbService.database;

    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      final batch = db.batch();
      for (var request in requests) {
        final mappedRequest = _mapBooleansToIntegers(request);
        if (ownerId != null) {
          mappedRequest['owner_id'] = ownerId;
        }
        batch.insert('tumpang_request', mappedRequest, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  // ownerId stays optional so callers who don't need scoping (e.g. code not
  // yet updated to pass an owner) keep working. When ownerId IS passed, the
  // column is guaranteed to exist (see _ensureOwnerIdColumn) so there is no
  // "missing column" fallback path here anymore — an owner-scoped query
  // either matches real rows for that owner or returns nothing, it never
  // silently widens to other accounts' data.
  Future<List<Map<String, dynamic>>> getOfflineRequests(String status, [String? ownerId]) async {
    await _ensureOwnerIdColumn();
    final db = await _dbService.readOnlyDatabase;

    final result = ownerId != null
        ? await db.query(
      'tumpang_request',
      where: 'status = ? AND owner_id = ?',
      whereArgs: [status, ownerId],
    )
        : await db.query(
      'tumpang_request',
      where: 'status = ?',
      whereArgs: [status],
    );

    return result.map((row) => _mapIntegersToBooleans(row)).toList();
  }

  Future<Map<String, dynamic>?> getOfflineRequestById(String id, [String? ownerId]) async {
    await _ensureOwnerIdColumn();
    final db = await _dbService.readOnlyDatabase;

    final result = ownerId != null
        ? await db.query(
      'tumpang_request',
      where: 'id = ? AND owner_id = ?',
      whereArgs: [id, ownerId],
    )
        : await db.query(
      'tumpang_request',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isNotEmpty) return _mapIntegersToBooleans(result.first);
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