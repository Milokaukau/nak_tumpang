import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class PaymentLocalService {
  final LocalDbService _dbService = LocalDbService();

  // INSERT OR REPLACE (Upsert) to cache payments from Supabase
  Future<void> cachePayments(List<Map<String, dynamic>> payments) async {
    final db = await _dbService.database;
    final batch = db.batch();

    for (var payment in payments) {
      batch.insert(
        'payments',
        payment,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // SELECT for offline viewing (Pending: paid_at IS NULL, Complete: paid_at IS NOT NULL)
  Future<List<Map<String, dynamic>>> getOfflinePayments({required bool isCompleted}) async {
    final db = await _dbService.database;

    final whereClause = isCompleted ? 'paid_at IS NOT NULL' : 'paid_at IS NULL';

    return await db.query(
      'payments',
      where: whereClause,
      orderBy: 'due_date DESC',
    );
  }

  // DELETE to clear cache upon logout
  Future<void> clearPaymentsCache() async {
    final db = await _dbService.database;
    await db.delete('payments');
  }
}