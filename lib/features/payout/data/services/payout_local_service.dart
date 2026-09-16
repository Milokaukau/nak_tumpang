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
    final db = await _dbService.readOnlyDatabase;
    final rows = await db.query('driver_profiles', where: 'user_id = ?', whereArgs: [userId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  // ---------------- driver_wallet_trips ----------------
  // Backs the Wallet tab's "Recent transactions" list and its two stat
  // boxes offline. Written only after a successful _loadWalletData()
  // round-trip, same rule as every other cache method here.

  /// Replaces this driver's cached wallet rows wholesale. A full replace
  /// (inside one transaction) rather than an upsert: `in_month` and
  /// `is_recent` are both relative to *when the fetch ran*, so a row
  /// that has since dropped out of the last-10 or out of the current
  /// month has to lose its flag — upserting would leave stale rows
  /// flagged forever and inflate the stat boxes month after month.
  Future<void> cacheDriverWalletTrips({
    required String userId,
    required List<Map<String, dynamic>> monthRows,
    required List<Map<String, dynamic>> recentRows,
  }) async {
    final db = await _dbService.database;

    // Merge by payment id first — a row can legitimately be both in the
    // current month and in the last 10, and it should only be stored once.
    final merged = <String, Map<String, dynamic>>{};

    void put(Map<String, dynamic> row, {required bool inMonth, required bool isRecent}) {
      final id = row['id']?.toString();
      if (id == null) return;
      final subscription = row['tumpang_subscription'] as Map<String, dynamic>?;
      final driverTrip = subscription?['driver_trips'] as Map<String, dynamic>?;
      final existing = merged[id];
      merged[id] = {
        'id': id,
        'user_id': userId,
        // The month query selects fewer columns than the recent one, so
        // when the same payment arrives from both, keep whichever pass
        // supplied a real value instead of letting the leaner row blank
        // the display fields out.
        'passenger_name': subscription?['passenger_trips']?['users']?['name'] as String? ??
            existing?['passenger_name'],
        'trip_name': driverTrip?['trip_name'] as String? ?? existing?['trip_name'],
        'pickup_name': subscription?['pickup_location'] as String? ?? existing?['pickup_name'],
        'dropoff_name': subscription?['dropoff_location'] as String? ?? existing?['dropoff_name'],
        'points': (row['driver_net_amount'] as num?)?.toDouble() ?? existing?['points'],
        'gross_amount': (row['amount'] as num?)?.toDouble() ?? existing?['gross_amount'],
        'platform_fee': (row['platform_fee'] as num?)?.toDouble() ?? existing?['platform_fee'],
        'daily_fee': double.tryParse(subscription?['fee']?.toString() ?? '') ?? existing?['daily_fee'],
        'cycle_start_date': row['cycle_start_date'] as String? ?? existing?['cycle_start_date'],
        'cycle_end_date': row['cycle_end_date'] as String? ?? existing?['cycle_end_date'],
        'paid_at': row['paid_at'] as String? ?? existing?['paid_at'],
        'in_month': (inMonth || existing?['in_month'] == 1) ? 1 : 0,
        'is_recent': (isRecent || existing?['is_recent'] == 1) ? 1 : 0,
      };
    }

    for (final row in monthRows) {
      put(row, inMonth: true, isRecent: false);
    }
    for (final row in recentRows) {
      put(row, inMonth: false, isRecent: true);
    }

    await db.transaction((txn) async {
      await txn.delete('driver_wallet_trips', where: 'user_id = ?', whereArgs: [userId]);
      final batch = txn.batch();
      for (final row in merged.values) {
        batch.insert('driver_wallet_trips', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getCachedRecentWalletTrips(String userId) async {
    final db = await _dbService.readOnlyDatabase;
    return db.query(
      'driver_wallet_trips',
      where: 'user_id = ? AND is_recent = 1',
      whereArgs: [userId],
      orderBy: 'paid_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getCachedMonthWalletTrips(String userId) async {
    final db = await _dbService.readOnlyDatabase;
    return db.query(
      'driver_wallet_trips',
      where: 'user_id = ? AND in_month = 1',
      whereArgs: [userId],
    );
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
    final db = await _dbService.readOnlyDatabase;
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
    final db = await _dbService.readOnlyDatabase;
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

  // ---------------- pending_payout_reconciliation ----------------
  // Payouts whose terminal status was decided locally but failed to
  // persist to payout_history even after one retry — see
  // PayoutViewModel.runPayoutStatusAnimation. Kept here (not just an
  // in-memory Set) so a reconciliation still applies after the app
  // restarts, and consumed by PayoutViewModel before it trusts a
  // freshly-fetched server status for the same payout.

  Future<void> savePendingReconciliation(String payoutId, String status) async {
    final db = await _dbService.database;
    await _upsert(db, 'pending_payout_reconciliation', 'payout_id', {
      'payout_id': payoutId,
      'status': status,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removePendingReconciliation(String payoutId) async {
    final db = await _dbService.database;
    await db.delete('pending_payout_reconciliation', where: 'payout_id = ?', whereArgs: [payoutId]);
  }

  // payoutId -> intended terminal status
  Future<Map<String, String>> getPendingReconciliations() async {
    final db = await _dbService.readOnlyDatabase;
    final rows = await db.query('pending_payout_reconciliation');
    return {for (final row in rows) row['payout_id'] as String: row['status'] as String};
  }

  // ---------------- payout_settings (single row) ----------------

  Future<void> cacheBankTransferFee(double fee) async {
    final db = await _dbService.database;
    await _upsert(db, 'payout_settings', 'id', {'id': 1, 'bank_transfer_fee': fee});
  }

  Future<double?> getCachedBankTransferFee() async {
    final db = await _dbService.readOnlyDatabase;
    final rows = await db.query('payout_settings', limit: 1);
    if (rows.isEmpty) return null;
    return (rows.first['bank_transfer_fee'] as num?)?.toDouble();
  }
}