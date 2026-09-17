import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class NegotiationLocalService {
  final LocalDbService _dbService = LocalDbService.instance;

  bool _ownerIdColumnReady = false;

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

  Future<void> clearRequestsCache() async {
    final db = await _dbService.database;
    await db.delete('tumpang_request');
  }

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