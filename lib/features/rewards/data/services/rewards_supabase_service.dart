import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

class RewardsSupabaseService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> fetchPointsSummary(String userId) async {
    try {
      // Sweep: zero out any batches that expired since we last checked, so
      // avai_points in the DB itself stays accurate for any other query
      // that might read this table directly.
      await _supabase
          .from('reward_points')
          .update({'avai_points': 0})
          .eq('user_id', userId)
          .gt('avai_points', 0)
          .lt('expired_at', DateTime.now().toIso8601String());
      final response = await _supabase
          .from('reward_points')
          .select()
          .eq('user_id', userId);

      final rows = List<Map<String, dynamic>>.from(response);
      final now = DateTime.now();

      int obtained = 0;
      int available = 0;
      int expiredUnused = 0; // points that lapsed without being spent
      DateTime? nearestExpiry;

      for (var row in rows) {
        final obtainedPts = (row['obtained_points'] as num).toInt();
        final avai = (row['avai_points'] as num).toInt();
        obtained += obtainedPts;

        final expiry = DateTime.tryParse(row['expired_at'] ?? '');
        final isExpired = expiry != null && now.isAfter(expiry);

        if (isExpired) {
          // Expired batches no longer count toward available balance,
          // regardless of how many points were left unspent in them.
          expiredUnused += avai;
        } else {
          available += avai;
          if (avai > 0 && expiry != null &&
              (nearestExpiry == null || expiry.isBefore(nearestExpiry))) {
            nearestExpiry = expiry;
          }
        }
      }

      final voucherCountResponse = await _supabase
          .from('user_vouchers')
          .select('id')
          .eq('user_id', userId);

      return {
        'obtained_points': obtained,
        'available_points': available,
        'used_points': obtained - available - expiredUnused,
        'expired_points': expiredUnused,
        'voucher_count': (voucherCountResponse as List).length,
        'nearest_expiry': nearestExpiry,
      };
    } catch (e) {
      print('Error in fetchPointsSummary: $e');
      return {
        'obtained_points': 0,
        'available_points': 0,
        'used_points': 0,
        'expired_points': 0,
        'voucher_count': 0,
        'nearest_expiry': null,
      };
    }
  }

  Future<List<Map<String, dynamic>>> fetchPointsHistory(String userId) async {
    try {
      final response = await _supabase
          .from('points_ledger')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error in fetchPointsHistory: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchAvailableVouchers(String userId) async {
    try {
      final allVouchers = await _supabase
          .from('vouchers')
          .select()
          .eq('open_for_redeem', true)
          .order('req_points', ascending: true);

      final redeemedResponse = await _supabase
          .from('user_vouchers')
          .select('voucher_id, code')
          .eq('user_id', userId);

      // Only a POINT-redeemed voucher (code doesn't start with 'GOYANG-')
      // counts as "already redeemed" here. A Goyang-won voucher is a free
      // lucky win — it should still show as redeemable via points too.
      final pointRedeemedIds = (redeemedResponse as List)
          .where((r) => !(r['code']?.toString().startsWith('GOYANG-') ?? false))
          .map((r) => r['voucher_id'])
          .toSet();

      return List<Map<String, dynamic>>.from(allVouchers).map((v) {
        return {
          ...v,
          'is_redeemed': pointRedeemedIds.contains(v['id']),
        };
      }).toList();
    } catch (e) {
      print('Error in fetchAvailableVouchers: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchMyVouchers(String userId) async {
    try {
      final response = await _supabase
          .from('user_vouchers')
          .select('*, vouchers(*)')
          .eq('user_id', userId)
          .order('obtained_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error in fetchMyVouchers: $e');
      return [];
    }
  }

  /// Redeems a voucher: blocks duplicate redemption, deducts points FIFO
  /// across reward_points batches, creates a user_vouchers row, and logs
  /// the redemption in points_ledger.
  Future<bool> redeemVoucher({
    required String userId,
    required Map<String, dynamic> voucher,
  }) async {
    final requiredPoints = (voucher['req_points'] as num).toInt();

    try {
      // Block re-redemption of the same voucher by the same user via points
// (a Goyang win of the same voucher doesn't count — that's free, not
// paid for with points, so it shouldn't block a real redemption).
      final existing = await _supabase
          .from('user_vouchers')
          .select('id, code')
          .eq('user_id', userId)
          .eq('voucher_id', voucher['id']);

      final alreadyPointRedeemed = (existing as List)
          .any((r) => !(r['code']?.toString().startsWith('GOYANG-') ?? false));
      if (alreadyPointRedeemed) {
        print('User already redeemed this voucher via points.');
        return false;
      }

      // Fetch spendable batches, oldest first (FIFO)
      final response = await _supabase
          .from('reward_points')
          .select()
          .eq('user_id', userId)
          .gt('avai_points', 0)
          .gt('expired_at', DateTime.now().toIso8601String())
          .order('obtained_at', ascending: true);

      final batches = List<Map<String, dynamic>>.from(response);

      int totalAvailable = 0;
      for (var b in batches) {
        totalAvailable += (b['avai_points'] as num).toInt();
      }
      if (totalAvailable < requiredPoints) {
        return false; // insufficient points
      }

      // Deduct across batches
      int remaining = requiredPoints;
      for (var batch in batches) {
        if (remaining <= 0) break;
        final avai = (batch['avai_points'] as num).toInt();
        final deduct = avai < remaining ? avai : remaining;
        await _supabase
            .from('reward_points')
            .update({'avai_points': avai - deduct})
            .eq('id', batch['id']);
        remaining -= deduct;
      }

      // Create the voucher redemption record
      final voucherId = voucher['id'];
      final validityDays = (voucher['validity_days'] as num).toInt();
      final now = DateTime.now();
      final expiredAt = now.add(Duration(days: validityDays));
      final userVoucherId = 'uv_${DateTime.now().millisecondsSinceEpoch}';
      final code = 'TUMPANG-${voucherId.toString().toUpperCase()}-${userId.substring(0, 6).toUpperCase()}';

      await _supabase.from('user_vouchers').insert({
        'id': userVoucherId,
        'user_id': userId,
        'voucher_id': voucherId,
        'code': code,
        'obtained_at': now.toIso8601String(),
        'expired_at': expiredAt.toIso8601String(),
        'used_at': null,
      });

      // Log the redemption
      await _supabase.from('points_ledger').insert({
        'id': 'pl_${DateTime.now().millisecondsSinceEpoch}',
        'user_id': userId,
        'change_amount': -requiredPoints,
        'reason': 'voucher_redeemed',
        'reference_id': userVoucherId,
        'description': 'Redeemed for ${voucher['name']}',
        'created_at': now.toIso8601String(),
      });

      return true;
    } catch (e) {
      print('Error in redeemVoucher: $e');
      return false;
    }
  }


  Future<bool> hasClaimedGoyangToday(String userId) async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

      final response = await _supabase
          .from('points_ledger')
          .select('id')
          .eq('user_id', userId)
          .inFilter('reason', ['goyang_points', 'goyang_voucher'])
          .gte('created_at', todayStart);

      return (response as List).isNotEmpty;
    } catch (e) {
      print('Error in hasClaimedGoyangToday: $e');
      return false;
    }
  }

  /// Plays one Goyang round: picks either a points bonus or a random
  /// in-stock voucher, grants it, and logs it so it shows up in Points
  /// History regardless of which outcome hit. Returns a result map:
  /// {'type': 'points', 'points': int} | {'type': 'voucher', 'voucher_name': String}
  /// | {'type': 'already_claimed'} | {'type': 'error'}
  Future<Map<String, dynamic>> playGoyang(String userId) async {
    try {
      if (await hasClaimedGoyangToday(userId)) {
        return {'type': 'already_claimed'};
      }

      final eligibleVouchers = await _supabase
          .from('vouchers')
          .select()
          .eq('open_for_redeem', true)
          .or('stock_quantity.is.null,stock_quantity.gt.0');

      final vouchers = List<Map<String, dynamic>>.from(eligibleVouchers);
      final random = Random();
      // 25% chance of a voucher outcome (only if any are actually in stock),
      // otherwise it's a points bonus.
      final bool tryVoucher = vouchers.isNotEmpty && random.nextDouble() < 0.25;
      final now = DateTime.now();

      if (tryVoucher) {
        final voucher = vouchers[random.nextInt(vouchers.length)];
        final voucherId = voucher['id'];

        // Re-check stock right before committing, in case it changed between
        // the list fetch above and now (best-effort for assignment scope —
        // not a true atomic decrement, same caveat as redeemVoucher's FIFO logic).
        final freshVoucher = await _supabase.from('vouchers').select().eq('id', voucherId).maybeSingle();
        final stock = freshVoucher?['stock_quantity'];
        if (stock != null && stock <= 0) {
          return await _grantGoyangPoints(userId, now);
        }

        if (stock != null) {
          await _supabase.from('vouchers').update({'stock_quantity': stock - 1}).eq('id', voucherId);
        }

        final validityDays = (voucher['validity_days'] as num).toInt();
        final expiredAt = now.add(Duration(days: validityDays));
        final userVoucherId = 'uv_${now.millisecondsSinceEpoch}_goyang';
        final code = 'GOYANG-${voucherId.toString().toUpperCase()}-${userId.substring(0, 6).toUpperCase()}';

        await _supabase.from('user_vouchers').insert({
          'id': userVoucherId,
          'user_id': userId,
          'voucher_id': voucherId,
          'code': code,
          'obtained_at': now.toIso8601String(),
          'expired_at': expiredAt.toIso8601String(),
          'used_at': null,
        });

        await _supabase.from('points_ledger').insert({
          'id': 'pl_${now.millisecondsSinceEpoch}_goyang',
          'user_id': userId,
          'change_amount': 0,
          'reason': 'goyang_voucher',
          'reference_id': userVoucherId,
          'description': 'Goyang N Win — won ${voucher['name']}',
          'created_at': now.toIso8601String(),
        });

        return {'type': 'voucher', 'voucher_name': voucher['name']};
      } else {
        return await _grantGoyangPoints(userId, now);
      }
    } catch (e) {
      print('Error in playGoyang: $e');
      return {'type': 'error'};
    }
  }

  Future<Map<String, dynamic>> _grantGoyangPoints(String userId, DateTime now) async {
    final points = [5, 10, 15, 20][Random().nextInt(4)];
    final rewardId = 'rp_${now.millisecondsSinceEpoch}_goyang';


    await _supabase.from('reward_points').insert({
      'id': rewardId,
      'user_id': userId,
      'obtained_points': points,
      'avai_points': points,
      'obtained_at': now.toIso8601String(),
      'expired_at': now.add(const Duration(days: 90)).toIso8601String(),
      // Goyang wins aren't tied to a real trip log, but the column is
      // NOT NULL and unique per (user_id, tumpang_trip_log_id) — a
      // synthetic, per-play-unique value satisfies both without a real
      // trip log row. The daily-limit guard (hasClaimedGoyangToday)
      // already prevents a user from ever needing two of these on the
      // same day, so uniqueness in practice is a non-issue.
      'tumpang_trip_log_id': 'goyang_${now.millisecondsSinceEpoch}',
    });

    await _supabase.from('points_ledger').insert({
      'id': 'pl_${now.millisecondsSinceEpoch}_goyang',
      'user_id': userId,
      'change_amount': points,
      'reason': 'goyang_points',
      'reference_id': rewardId,
      'description': 'Goyang N Win — daily bonus',
      'created_at': now.toIso8601String(),
    });

    return {'type': 'points', 'points': points};
  }

  /// Raw reward_points rows for [userId] — used to populate the local cache
  /// so getCachedPointsSummary can recompute the same summary offline.
  Future<List<Map<String, dynamic>>> fetchRawRewardPoints(String userId) async {
    try {
      final response = await _supabase.from('reward_points').select().eq('user_id', userId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error in fetchRawRewardPoints: $e');
      return [];
    }
  }

  /// The full voucher catalog, unfiltered — used to populate the local
  /// cache. (fetchAvailableVouchers already filters out redeemed ones for
  /// display; this is the raw table for offline storage.)
  Future<List<Map<String, dynamic>>> fetchAllVouchers() async {
    try {
      final response = await _supabase.from('vouchers').select();
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error in fetchAllVouchers: $e');
      return [];
    }
  }
}