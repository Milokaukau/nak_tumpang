import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

// read caching to show wallet and history tabs when offline
class PayoutLocalService {
  final _dbService = LocalDbService.instance;

  // inserts if pkColumn's value isnt present yet
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

  // ---------------- driver_profiles (wallet balance columns only) ----------------

  Future<void> cacheWalletBalance({
    required String userId,
    required double totalEarnings,
    required double availableBalance,
    required double totalWithdrawn,
  }) async {
    final db = await _dbService.database;
    await _upsert(db, 'driver_profiles', 'user_id', {
      'user_id': userId,
      'total_earnings': totalEarnings,
      'available_balance': availableBalance,
      'total_withdrawn': totalWithdrawn,
    });
  }

  Future<Map<String, dynamic>?> getCachedWalletBalance(String userId) async {
    final db = await _dbService.database;
    final rows = await db.query('driver_profiles', where: 'user_id = ?', whereArgs: [userId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  // ---------------- payout_history ----------------

  // payout_history rows are always fetched as a full `select()`
  //a plain insert-or-replace is safe here — no risk of wiping sibling column
  Future<void> cachePayoutHistoryPage(List<Map<String, dynamic>> rows) async {
    final db = await _dbService.database;
    final batch = db.batch();
    for (final row in rows) {
      batch.insert('payout_history', row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> cachePayoutHistoryRow(Map<String, dynamic> row) async {
    final db = await _dbService.database;
    await db.insert('payout_history', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // offline behaves same way as live query
  Future<List<Map<String, dynamic>>> getCachedPayoutHistoryPage(
      String userId, {
        required int limit,
        required int offset,
        int? year,
        int? month, // 1-12; only meaningful together with `year`
      }) async {
    final db = await _dbService.database;
    var where = 'user_id = ?';
    final args = <Object?>[userId];

    if (year != null) {
      final startMonth = month ?? 1;
      final endMonth = month ?? 12;
      final start = DateTime(year, startMonth, 1);
      final end = DateTime(endMonth == 12 ? year + 1 : year, endMonth == 12 ? 1 : endMonth + 1, 1);
      where += ' AND requested_at >= ? AND requested_at < ?';
      args.addAll([start.toIso8601String(), end.toIso8601String()]);
    }

    return db.query(
      'payout_history',
      where: where,
      whereArgs: args,
      orderBy: 'requested_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<List<DateTime>> getCachedPayoutHistoryDates(String userId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'payout_history',
      columns: ['requested_at'],
      where: 'user_id = ? AND requested_at IS NOT NULL',
      whereArgs: [userId],
    );
    return rows
        .map((row) => DateTime.tryParse(row['requested_at'] as String? ?? ''))
        .whereType<DateTime>()
        .toList();
  }

  // updates the status of an already cached row
  // used by runPayoutStatusAnimation's terminal-status sync
  Future<void> updateCachedPayoutStatus(String id, String status, {DateTime? processedAt}) async {
    final db = await _dbService.database;
    await db.update(
      'payout_history',
      {
        'status': status,
        if (processedAt != null) 'processed_at': processedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------- payout_settings (single row) ----------------

  Future<void> cacheBankTransferFee(double fee) async {
    final db = await _dbService.database;
    await _upsert(db, 'payout_settings', 'id', {'id': 1, 'bank_transfer_fee': fee});
  }

  Future<double?> getCachedBankTransferFee() async {
    final db = await _dbService.database;
    final rows = await db.query('payout_settings', limit: 1);
    if (rows.isEmpty) return null;
    return (rows.first['bank_transfer_fee'] as num?)?.toDouble();
  }
}