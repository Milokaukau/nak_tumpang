import 'package:flutter/material.dart';
import 'package:nak_tumpang/features/subscriptions/data/services/subscription_supabase_service.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/subscriptions/data/services/subscription_local_service.dart';

class SubscriptionViewModel extends ChangeNotifier {
  final SubscriptionSupabaseService _service = SubscriptionSupabaseService();
  final SubscriptionLocalService _localService = SubscriptionLocalService();

  bool isLoading = false;
  List<Map<String, dynamic>> subscriptions = [];

  Future<void> fetchSubscriptions({
    required String userId,
    required String role,
  }) async {
    isLoading = true;
    notifyListeners();

    if (NetworkService.isOfflineNotifier.value) {
      subscriptions = await _localService.getCachedSubscriptionsForList(userId, role);
      isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final results = await _service.fetchSubscriptions(userId: userId, role: role);

      await Future.wait(results.map((sub) async {
        sub['has_active_exception'] = await _service.hasActiveException(sub['id']);
      }));

      subscriptions = results;
    } catch (e) {
      debugPrint('⚠️ Error loading subscriptions online, falling back to cache: $e');
      subscriptions = await _localService.getCachedSubscriptionsForList(userId, role);
    }

    isLoading = false;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> fetchExceptions(String subscriptionId) {
    return _service.fetchExceptionsForSubscription(subscriptionId);
  }

  Future<bool> cancelException(String exceptionId) {
    return _service.cancelException(exceptionId);
  }

  Future<bool> cancelSubscription({
    required String subscriptionId,
    required String cancelledByRole,
    String? reason,
    String? otherUserId,
  }) async {
    try {
      isLoading = true;
      notifyListeners();

      String targetUserId = otherUserId ?? '';

      if (targetUserId.isEmpty) {
        final sub = subscriptions.firstWhere(
              (s) => s['id'] == subscriptionId,
          orElse: () => <String, dynamic>{},
        );

        targetUserId = (cancelledByRole == 'driver'
            ? sub['passenger_id']
            : sub['driver_id']) ?? '';
      }

      final success = await _service.cancelSubscription(
        subscriptionId: subscriptionId,
        cancelledByRole: cancelledByRole,
        otherUserId: targetUserId,
        reason: reason,
      );

      isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      isLoading = false;
      notifyListeners();
      debugPrint('Error cancelling subscription: $e');
      return false;
    }
  }

  Future<bool> updateException({
    required String exceptionId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    required String otherUserId,
    String? subscriptionId,
  }) {
    return _service.updateException(
      exceptionId: exceptionId,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      otherUserId: otherUserId,
      subscriptionId: subscriptionId,
    );
  }

  Future<List<Map<String, dynamic>>> fetchAllExceptions(String subscriptionId) {
    return _service.fetchAllExceptionsForSubscription(subscriptionId);
  }
}