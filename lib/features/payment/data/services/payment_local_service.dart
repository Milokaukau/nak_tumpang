import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class PaymentLocalService {
  // Use the singleton instance defined by your team lead
  final LocalDbService _dbService = LocalDbService.instance;

  // INSERT OR REPLACE (Upsert) to cache payments from Supabase
  Future<void> cachePayments(List<Map<String, dynamic>> payments) async {
    final db = await _dbService.database;

    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      final batch = db.batch();
      for (var payment in payments) {
        batch.insert(
          'payments',
          payment,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future<List<Map<String, dynamic>>> getOfflinePayments({required bool isCompleted}) async {
    final db = await _dbService.readOnlyDatabase;

    final whereClause = isCompleted ? 'paid_at IS NOT NULL' : 'paid_at IS NULL';

    return await db.query(
      'payments',
      where: whereClause,
      orderBy: 'due_date DESC',
    );
  }

  // NEW FIX: Ensures clicking an invoice button/link offline can load immediately.
  Future<Map<String, dynamic>?> getOfflinePaymentById(String id) async {
    final db = await _dbService.readOnlyDatabase;
    final result = await db.query(
      'payments',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isNotEmpty) return result.first;
    return null;
  }

  Future<void> deletePaymentsByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbService.database;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete('payments', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  // DELETE to clear cache upon logout
  Future<void> clearPaymentsCache() async {
    final db = await _dbService.database;
    await db.delete('payments');
  }
}