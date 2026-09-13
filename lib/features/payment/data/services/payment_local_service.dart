import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class PaymentLocalService {
  // Use the singleton instance defined by your team lead
  final LocalDbService _dbService = LocalDbService.instance;

  // INSERT OR REPLACE (Upsert) to cache payments from Supabase
  Future<void> cachePayments(List<Map<String, dynamic>> payments) async {
    final db = await _dbService.database;

    // Temporarily bypass strict foreign key rules to allow partial caching.
    // Wrapped in try/finally — see NegotiationLocalService.cacheTumpangRequests
    // for why: a failed batch.commit() must not leave foreign_keys OFF for
    // every later write on this shared connection.
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
      // Restore the strict rules to respect the team lead's configuration —
      // runs even if batch.commit() above threw.
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  // SELECT for offline viewing (Pending: paid_at IS NULL, Complete: paid_at IS NOT NULL)
  //
  // NOTE ON ACCOUNT SCOPING: this table has no owner/user-id column to
  // filter by, so this cache is only ever safe to hold ONE account's data
  // at a time. PaymentViewModel is responsible for calling
  // [clearPaymentsCache] on logout and on switching to a different account
  // (see its auth-state listener) so a second user on the same device can
  // never read a previous user's cached payment history.
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