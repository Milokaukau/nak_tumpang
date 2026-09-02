import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/payment.dart';
import 'package:nak_tumpang/features/payment/data/services/payment_supabase_service.dart';

class PaymentViewModel extends ChangeNotifier {
  final PaymentSupabaseService _service = PaymentSupabaseService();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Payment> pendingPayments = [];
  Set<String> selectedPaymentIds = {};

  bool isLoading = false;
  String? errorMessage;

  PaymentViewModel() {
    _supabase.auth.onAuthStateChange.listen((data) {
      // Fallback to currentSession in case the stream data is momentarily empty on boot
      final session = data.session ?? _supabase.auth.currentSession;

      if (session != null) {
        errorMessage = null;
        fetchPayments();
      } else {
        pendingPayments.clear();
        selectedPaymentIds.clear();

        // ONLY show the login error if they explicitly pressed Sign Out
        if (data.event == AuthChangeEvent.signedOut) {
          errorMessage = 'User not authenticated. Please log in.';
        } else {
          errorMessage = null;
        }

        notifyListeners();
      }
    });
  }

  double get totalSelectedAmount {
    return pendingPayments
        .where((p) => selectedPaymentIds.contains(p.id))
        .fold(0, (sum, item) => sum + item.amount);
  }

  Future<void> fetchPayments() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      pendingPayments = await _service.fetchPendingPayments(userId);
    } catch (e) {
      errorMessage = 'Failed to load payments: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void toggleSelection(String id) {
    if (selectedPaymentIds.contains(id)) {
      selectedPaymentIds.remove(id);
    } else {
      selectedPaymentIds.add(id);
    }
    notifyListeners();
  }

  Future<bool> processMockPayment(String paymentMethod) async {
    isLoading = true;
    notifyListeners();

    try {
      for (final id in selectedPaymentIds) {
        await _service.completePayment(
          paymentId: id,
          paymentMethod: paymentMethod,
        );
      }

      selectedPaymentIds.clear();
      await fetchPayments();
      return true;
    } catch (e) {
      errorMessage = 'Payment failed: $e';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}