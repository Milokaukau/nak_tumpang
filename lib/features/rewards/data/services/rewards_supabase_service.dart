import 'package:supabase_flutter/supabase_flutter.dart';

class RewardsSupabaseService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> fetchPointsSummary(String userId) async {
    try {
      final response = await _supabase
          .from('reward_points')
          .select()
          .eq('user_id', userId);

      final rows = List<Map<String, dynamic>>.from(response);
      int obtained = 0;
      int available = 0;
      DateTime? nearestExpiry;

      for (var row in rows) {
        obtained += (row['obtained_points'] as num).toInt();
        final avai = (row['avai_points'] as num).toInt();
        available += avai;
        if (avai > 0) {
          final expiry = DateTime.tryParse(row['expired_at'] ?? '');
          if (expiry != null && (nearestExpiry == null || expiry.isBefore(nearestExpiry))) {
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
        'used_points': obtained - available,
        'voucher_count': (voucherCountResponse as List).length,
        'nearest_expiry': nearestExpiry,
      };
    } catch (e) {
      print('Error in fetchPointsSummary: $e');
      return {
        'obtained_points': 0,
        'available_points': 0,
        'used_points': 0,
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
          .select('voucher_id')
          .eq('user_id', userId);

      final redeemedIds = (redeemedResponse as List).map((r) => r['voucher_id']).toSet();

      return List<Map<String, dynamic>>.from(allVouchers)
          .where((v) => !redeemedIds.contains(v['id']))
          .toList();
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
      // Block re-redemption of the same voucher by the same user
      final existing = await _supabase
          .from('user_vouchers')
          .select('id')
          .eq('user_id', userId)
          .eq('voucher_id', voucher['id']);
      if ((existing as List).isNotEmpty) {
        print('User already redeemed this voucher.');
        return false;
      }

      // Fetch spendable batches, oldest first (FIFO)
      final response = await _supabase
          .from('reward_points')
          .select()
          .eq('user_id', userId)
          .gt('avai_points', 0)
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
}