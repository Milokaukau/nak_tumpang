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

    // Run exception checks in parallel for faster load times
    await Future.wait(results.map((sub) async {
      sub['has_active_exception'] = await _service.hasActiveException(sub['id']);
    }));

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
    String? reason,
  }) async {
    try {
      isLoading = true; // Fixed: removed underscore
      notifyListeners();

      // Fixed: Delegating to your service layer to match your architecture
      final success = await _service.cancelSubscription(
        subscriptionId: subscriptionId,
        cancelledByRole: cancelledByRole,
        reason: reason,
      );

      isLoading = false; // Fixed: removed underscore
      notifyListeners();
      return success;
    } catch (e) {
      isLoading = false; // Fixed: removed underscore
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
  }) {
    return _service.updateException(
      exceptionId: exceptionId,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
    );
  }

  Future<String?> createExtensionRequest({
    required Map<String, dynamic> oldSubscription,
    required DateTime newStartDate,
    required DateTime newEndDate,
  }) async {
    isLoading = true;
    notifyListeners();

    final newRequestId = await _service.createExtensionRequest(
      oldSubscription: oldSubscription,
      newStartDate: newStartDate,
      newEndDate: newEndDate,
    );

    isLoading = false;
    notifyListeners();

    return newRequestId; // Will be null if it failed, or the ID if it succeeded
  }
}

