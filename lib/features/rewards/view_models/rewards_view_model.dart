import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/rewards/data/services/rewards_supabase_service.dart';
import 'package:nak_tumpang/features/rewards/data/services/rewards_local_service.dart';

class RewardsViewModel extends ChangeNotifier {
  final RewardsSupabaseService _service = RewardsSupabaseService();
  final RewardsLocalService _localService = RewardsLocalService();

  bool isGoyangAvailableToday = true;
  bool isClaimingGoyang = false;
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

    if (NetworkService.isOfflineNotifier.value) {
      await _loadFromCache(userId);
      isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final rawRewardPoints = await _service.fetchRawRewardPoints(userId);
      final rawVouchers = await _service.fetchAllVouchers();

      summary = await _service.fetchPointsSummary(userId);
      pointsHistory = await _service.fetchPointsHistory(userId);
      availableVouchers = await _service.fetchAvailableVouchers(userId);
      myVouchers = await _service.fetchMyVouchers(userId);


      try {
        await _localService.cacheRewardPoints(userId, rawRewardPoints);
        await _localService.cachePointsLedger(userId, pointsHistory);
        await _localService.cacheVouchers(rawVouchers);
        await _localService.cacheUserVouchers(userId, myVouchers);
      } catch (e) {
        debugPrint('⚠️ Error caching rewards data locally: $e');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading rewards online, falling back to cache: $e');
      await _loadFromCache(userId);
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> _loadFromCache(String userId) async {
    summary = await _localService.getCachedPointsSummary(userId);
    pointsHistory = await _localService.getCachedPointsHistory(userId);
    availableVouchers = await _localService.getCachedAvailableVouchers(userId);
    myVouchers = await _localService.getCachedMyVouchers(userId);
  }

  Future<bool> redeemVoucher(String userId, Map<String, dynamic> voucher) async {
    final success = await _service.redeemVoucher(userId: userId, voucher: voucher);
    if (success) {
      await loadAll(userId);
    }
    return success;
  }

  Future<void> checkGoyangAvailability(String userId) async {
    if (NetworkService.isOfflineNotifier.value) {
      isGoyangAvailableToday = false;
      notifyListeners();
      return;
    }
    final claimed = await _service.hasClaimedGoyangToday(userId);
    isGoyangAvailableToday = !claimed;
    notifyListeners();
  }

  Future<Map<String, dynamic>> playGoyang(String userId) async {
    if (isClaimingGoyang || !isGoyangAvailableToday) return {'type': 'unavailable'};
    isClaimingGoyang = true;
    notifyListeners();

    final result = await _service.playGoyang(userId);
    if (result['type'] == 'points' || result['type'] == 'voucher') {
      isGoyangAvailableToday = false;
      await loadAll(userId);
    }

    isClaimingGoyang = false;
    notifyListeners();
    return result;
  }
}