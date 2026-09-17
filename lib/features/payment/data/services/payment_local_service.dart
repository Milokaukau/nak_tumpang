import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class PaymentLocalService {
  final LocalDbService _dbService = LocalDbService.instance;

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
    final orderBy = isCompleted ? 'due_date DESC' : 'due_date ASC';

    return await db.query(
      'payments',
      where: whereClause,
      orderBy: orderBy,
    );
  }

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

  Future<void> clearPaymentsCache() async {
    final db = await _dbService.database;
    await db.delete('payments');
  }
}