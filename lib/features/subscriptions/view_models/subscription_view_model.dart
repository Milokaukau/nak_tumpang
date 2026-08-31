import 'package:flutter/material.dart';
import 'package:nak_tumpang/features/subscriptions/data/services/subscription_supabase_service.dart';

class SubscriptionViewModel extends ChangeNotifier {
  final SubscriptionSupabaseService _service = SubscriptionSupabaseService();

  bool isLoading = false;
  List<Map<String, dynamic>> subscriptions = [];

  Future<void> fetchSubscriptions({
    required String userId,
    required String role,
  }) async {
    isLoading = true;
    notifyListeners();

    final results = await _service.fetchSubscriptions(userId: userId, role: role);

    for (var sub in results) {
      sub['has_active_exception'] = await _service.hasActiveException(sub['id']);
    }

    subscriptions = results;
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
  }) {
    return _service.cancelSubscription(
      subscriptionId: subscriptionId,
      cancelledByRole: cancelledByRole,
    );
  }
}