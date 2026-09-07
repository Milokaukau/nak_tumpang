import 'package:flutter/material.dart';
import 'package:nak_tumpang/features/rewards/data/services/rewards_supabase_service.dart';

class RewardsViewModel extends ChangeNotifier {
  final RewardsSupabaseService _service = RewardsSupabaseService();

  bool isLoading = false;
  Map<String, dynamic> summary = {
    'obtained_points': 0,
    'available_points': 0,
    'used_points': 0,
    'voucher_count': 0,
    'nearest_expiry': null,
  };
  List<Map<String, dynamic>> pointsHistory = [];
  List<Map<String, dynamic>> availableVouchers = [];
  List<Map<String, dynamic>> myVouchers = [];

  Future<void> loadAll(String userId) async {
    isLoading = true;
    notifyListeners();

    summary = await _service.fetchPointsSummary(userId);
    pointsHistory = await _service.fetchPointsHistory(userId);
    availableVouchers = await _service.fetchAvailableVouchers(userId);
    myVouchers = await _service.fetchMyVouchers(userId);

    isLoading = false;
    notifyListeners();
  }

  Future<bool> redeemVoucher(String userId, Map<String, dynamic> voucher) async {
    final success = await _service.redeemVoucher(userId: userId, voucher: voucher);
    if (success) {
      await loadAll(userId); // refresh everything after a successful redemption
    }
    return success;
  }
}