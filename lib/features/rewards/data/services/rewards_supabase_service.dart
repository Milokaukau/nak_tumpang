import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';

class RewardsSupabaseService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> fetchPointsSummary(String userId) async {
    try {
      final response = await _supabase
          .from('reward_points')
          .select()
          .eq('user_id', userId);

      final rows = List<Map<String, dynamic>>.from(response);
      final now = DateTime.now();

      int obtained = 0;
      int available = 0;
      int expiredUnused = 0;
      DateTime? nearestExpiry;
      final List<String> idsToZeroOut = [];

      for (var row in rows) {
        final obtainedPts = (row['obtained_points'] as num).toInt();
        final avai = (row['avai_points'] as num).toInt();
        obtained += obtainedPts;

        final expiry = DateTime.tryParse(row['expired_at'] ?? '');
        final isExpired = expiry != null && now.isAfter(expiry);

        if (isExpired) {
          if (avai > 0) {
            expiredUnused += avai;
            idsToZeroOut.add(row['id'].toString());
          }
        } else {
          available += avai;
          if (avai > 0 && expiry != null &&
              (nearestExpiry == null || expiry.isBefore(nearestExpiry))) {
            nearestExpiry = expiry;
          }
        }
      }

      if (idsToZeroOut.isNotEmpty) {
        await _supabase
            .from('reward_points')
            .update({'avai_points': 0})
            .inFilter('id', idsToZeroOut);
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

  Future<bool> redeemVoucher({
    required String userId,
    required Map<String, dynamic> voucher,
  }) async {
    final requiredPoints = (voucher['req_points'] as num).toInt();
    final voucherId = voucher['id'];

    try {
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

      final freshVoucher = await _supabase
          .from('vouchers')
          .select('stock_quantity')
          .eq('id', voucherId)
          .maybeSingle();

      final currentStock = freshVoucher?['stock_quantity'];
      if (currentStock != null && (currentStock as num).toInt() <= 0) {
        print('Voucher $voucherId is out of stock.');
        return false;
      }

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
        return false;
      }

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

      if (currentStock != null) {
        final updateResult = await _supabase
            .from('vouchers')
            .update({'stock_quantity': (currentStock as num).toInt() - 1})
            .eq('id', voucherId)
            .select();

        debugPrint('🔍 Stock update result: $updateResult, currentStock was: $currentStock, voucherId: $voucherId');
      }

      final validityDays = (voucher['validity_days'] as num).toInt();
      final now = DateTime.now();
      final expiredAt = now.add(Duration(days: validityDays));
      final userVoucherId = 'uv_${DateTime.now().millisecondsSinceEpoch}';
      final code = 'TUMPANG-${voucherId.toString().toUpperCase()}-${userId.substring(0, 6).toUpperCase()}-${now.millisecondsSinceEpoch}';

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
      final bool tryVoucher = vouchers.isNotEmpty && random.nextDouble() < 0.25;
      final now = DateTime.now();

      if (tryVoucher) {
        final voucher = vouchers[random.nextInt(vouchers.length)];
        final voucherId = voucher['id'];

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
        final code = 'GOYANG-${voucherId.toString().toUpperCase()}-${userId.substring(0, 6).toUpperCase()}-${now.millisecondsSinceEpoch}';

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

  Future<List<Map<String, dynamic>>> fetchRawRewardPoints(String userId) async {
    try {
      final response = await _supabase.from('reward_points').select().eq('user_id', userId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error in fetchRawRewardPoints: $e');
      return [];
    }
  }

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