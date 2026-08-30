import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/payment.dart';

class PaymentSupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _table = 'payments';

  // Fetches pending payments dynamically where paid_at has not been set
  Future<List<Payment>> fetchPendingPayments(String userId) async {
    final response = await _supabase
        .from(_table)
        .select()
        .isFilter('paid_at', null);

    return response.map((json) => Payment.fromJson(json)).toList();
  }

  // Updates the payment record timestamp dynamically upon settlement
  Future<void> completePayment({
    required String paymentId,
    required String paymentMethod,
  }) async {
    await _supabase.from(_table).update({
      'paid_at': DateTime.now().toIso8601String(),
    }).eq('id', paymentId);
  }
}