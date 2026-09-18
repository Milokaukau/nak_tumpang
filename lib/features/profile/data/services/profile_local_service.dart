import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class ProfileLocalService {
  final _dbService = LocalDbService.instance;

  Future<void> _upsert(
      Database db,
      String table,
      String pkColumn,
      Map<String, dynamic> data,
      ) async {
    final pkValue = data[pkColumn];
    final existing = await db.query(table, where: '$pkColumn = ?', whereArgs: [pkValue], limit: 1);
    if (existing.isEmpty) {
      await db.insert(table, data);
    } else {
      await db.update(table, data, where: '$pkColumn = ?', whereArgs: [pkValue]);
    }
  }

  Future<void> cacheUserProfile({
    required String userId,
    required String name,
    required String email,
    required String phone,
    required String role,
    String? avatarUrl,
  }) async {
    final db = await _dbService.database;
    await _upsert(db, 'users', 'id', {
      'id': userId,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'avatar_url': avatarUrl,
    });
  }

  Future<Map<String, dynamic>?> getCachedUserProfile(String userId) async {
    final db = await _dbService.database;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> cacheDriverLicense({
    required String userId,
    String? licenseNumber,
    String? licenseUrl,
  }) async {
    final db = await _dbService.database;
    await _upsert(db, 'driver_profiles', 'user_id', {
      'user_id': userId,
      'license_number': licenseNumber,
      'license_url': licenseUrl,
    });
  }

  Future<Map<String, dynamic>?> getCachedDriverLicense(String userId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'driver_profiles',
      columns: ['license_number', 'license_url'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }
}