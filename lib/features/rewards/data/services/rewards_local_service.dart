import 'package:sqflite/sqflite.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

class RewardsLocalService {
  final LocalDbService _dbService = LocalDbService.instance;

  Future<void> cacheRewardPoints(String userId, List<Map<String, dynamic>> rows) async {
    final db = await _dbService.database;

    await db.transaction((txn) async {
      final batch = txn.batch();

      batch.delete('reward_points', where: 'user_id = ?', whereArgs: [userId]);

      for (final r in rows) {
        batch.insert(
          'reward_points',
          {
            'id': r['id'],
            'user_id': userId,
            'obtained_points': r['obtained_points'],
            'avai_points': r['avai_points'],
            'obtained_at': r['obtained_at'],
            'expired_at': r['expired_at'],
            'tumpang_trip_log_id': r['tumpang_trip_log_id'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, dynamic>> getCachedPointsSummary(String userId) async {
    final db = await _dbService.database;
    final rows = await db.query('reward_points', where: 'user_id = ?', whereArgs: [userId]);

    int obtained = 0;
    int available = 0;
    DateTime? nearestExpiry;

    for (final row in rows) {
      obtained += (row['obtained_points'] as num).toInt();
      final avai = (row['avai_points'] as num).toInt();
      available += avai;
      if (avai > 0) {
        final expiry = DateTime.tryParse(row['expired_at']?.toString() ?? '');
        if (expiry != null && (nearestExpiry == null || expiry.isBefore(nearestExpiry))) {
          nearestExpiry = expiry;
        }
      }
    }

    final voucherCount = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM user_vouchers WHERE user_id = ?',
      [userId],
    )) ?? 0;

    return {
      'obtained_points': obtained,
      'available_points': available,
      'used_points': obtained - available,
      'voucher_count': voucherCount,
      'nearest_expiry': nearestExpiry,
    };
  }

  Future<void> cachePointsLedger(String userId, List<Map<String, dynamic>> rows) async {
    final db = await _dbService.database;

    await db.transaction((txn) async {
      final batch = txn.batch();

      batch.delete('points_ledger', where: 'user_id = ?', whereArgs: [userId]);

      for (final r in rows) {
        batch.insert(
          'points_ledger',
          {
            'id': r['id'],
            'user_id': userId,
            'change_amount': r['change_amount'],
            'reason': r['reason'],
            'reference_id': r['reference_id'],
            'description': r['description'],
            'created_at': r['created_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getCachedPointsHistory(String userId) async {
    final db = await _dbService.database;
    return db.query(
      'points_ledger',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> cacheVouchers(List<Map<String, dynamic>> rows) async {
    final db = await _dbService.database;

    await db.transaction((txn) async {
      final batch = txn.batch();

      batch.delete('vouchers');

      for (final v in rows) {
        batch.insert(
          'vouchers',
          {
            'id': v['id'],
            'name': v['name'],
            'description': v['description'],
            'validity_days': v['validity_days'],
            'tnc': v['tnc'],
            'open_for_redeem': (v['open_for_redeem'] == true) ? 1 : 0,
            'req_points': v['req_points'],
            'stock_quantity': v['stock_quantity'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });
  }

  Future<void> cacheUserVouchers(String userId, List<Map<String, dynamic>> rows) async {
    final db = await _dbService.database;

    await db.transaction((txn) async {
      final batch = txn.batch();

      batch.delete('user_vouchers', where: 'user_id = ?', whereArgs: [userId]);

      for (final uv in rows) {
        batch.insert(
          'user_vouchers',
          {
            'id': uv['id'],
            'user_id': userId,
            'voucher_id': uv['voucher_id'],
            'code': uv['code'],
            'obtained_at': uv['obtained_at'],
            'expired_at': uv['expired_at'],
            'used_at': uv['used_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getCachedAvailableVouchers(String userId) async {
    final db = await _dbService.database;

    final allVouchers = await db.query(
      'vouchers',
      where: 'open_for_redeem = ?',
      whereArgs: [1],
      orderBy: 'req_points ASC',
    );

    final redeemedRows = await db.query(
      'user_vouchers',
      columns: ['voucher_id', 'code'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    final pointRedeemedIds = redeemedRows
        .where((r) => !(r['code']?.toString().startsWith('GOYANG-') ?? false))
        .map((r) => r['voucher_id'])
        .toSet();

    return allVouchers.map((v) {
      return {
        ...v,
        'is_redeemed': pointRedeemedIds.contains(v['id']),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getCachedMyVouchers(String userId) async {
    final db = await _dbService.database;

    final results = await db.rawQuery('''
      SELECT
        uv.*,
        v.id AS v_id, v.name AS v_name, v.description AS v_description,
        v.validity_days AS v_validity_days, v.tnc AS v_tnc
      FROM user_vouchers uv
      INNER JOIN vouchers v ON uv.voucher_id = v.id
      WHERE uv.user_id = ?
      ORDER BY uv.obtained_at DESC
    ''', [userId]);

    return results.map((row) {
      return {
        'id': row['id'],
        'user_id': row['user_id'],
        'voucher_id': row['voucher_id'],
        'code': row['code'],
        'obtained_at': row['obtained_at'],
        'expired_at': row['expired_at'],
        'used_at': row['used_at'],
        'vouchers': {
          'id': row['v_id'],
          'name': row['v_name'],
          'description': row['v_description'],
          'validity_days': row['v_validity_days'],
          'tnc': row['v_tnc'],
        },
      };
    }).toList();
  }
}