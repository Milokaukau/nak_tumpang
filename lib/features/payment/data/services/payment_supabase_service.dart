import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/payment.dart';

class PaymentSupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _table = 'payments';

  Future<List<Payment>> fetchPendingPayments(String userId) async {
    try {
      final userTrips = await _supabase
          .from('passenger_trips')
          .select('id')
          .eq('user_id', userId);

      final tripIds = (userTrips as List).map((t) => t['id'] as String).toList();
      if (tripIds.isEmpty) return [];

      final subs = await _supabase
          .from('tumpang_subscription')
          .select('id')
          .inFilter('passenger_trip_id', tripIds);

      final subIds = (subs as List).map((s) => s['id'] as String).toList();
      if (subIds.isEmpty) return [];

      final List<dynamic> response = await _supabase
          .from(_table)
          .select('*, tumpang_subscription(pickup_location, dropoff_location)')
          .inFilter('tumpang_subscription_id', subIds)
          .isFilter('paid_at', null)
          .order('due_date', ascending: true);

      return response.map((json) => Payment.fromJson(json)).toList();
    } catch (e, stack) {
      debugPrint('Error fetching pending payments: $e\n$stack');
      rethrow;
    }
  }

  Future<List<Payment>> fetchPaymentHistory(String userId) async {
    try {
      final userTrips = await _supabase
          .from('passenger_trips')
          .select('id')
          .eq('user_id', userId);

      final tripIds = (userTrips as List).map((t) => t['id'] as String).toList();
      if (tripIds.isEmpty) return [];

      final subs = await _supabase
          .from('tumpang_subscription')
          .select('id')
          .inFilter('passenger_trip_id', tripIds);

      final subIds = (subs as List).map((s) => s['id'] as String).toList();
      if (subIds.isEmpty) return [];

      final List<dynamic> response = await _supabase
          .from(_table)
          .select('*, tumpang_subscription(pickup_location, dropoff_location)')
          .inFilter('tumpang_subscription_id', subIds)
          .not('paid_at', 'is', null)
          .order('paid_at', ascending: false);

      return response.map((json) => Payment.fromJson(json)).toList();
    } catch (e, stack) {
      debugPrint('Error fetching payment history: $e\n$stack');
      rethrow;
    }
  }

  Future<void> completePaymentBatch(List<String> paymentIds) async {
    final nowIso = DateTime.now().toIso8601String();
    await _supabase
        .from(_table)
        .update({'paid_at': nowIso})
        .inFilter('id', paymentIds);
  }
}