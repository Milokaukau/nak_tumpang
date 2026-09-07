import 'package:supabase_flutter/supabase_flutter.dart';

// data access to wallet
class PayoutService {
  final _supabase = Supabase.instance.client;


  Future<Map<String, dynamic>?> fetchDriverProfile(String userId) {
    return _supabase.from('driver_profiles').select().eq('user_id', userId).maybeSingle();
  }

  Future<List<Map<String, dynamic>>> fetchCompletedTrips(String userId) async {
    final response = await _supabase
        .from('tumpang_request')
        .select('''
          id,
          fee,
          pickup_name,
          dropoff_name,
          sub_start_date,
          driver_trips!inner(user_id),
          passenger_trips(user_id, users(name))
        ''')
        .eq('driver_trips.user_id', userId)
        .eq('status', 'completed')
        .order('sub_start_date', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // e-wallet payment method will have null bank names
  Future<String> requestPayout({
    required String userId,
    required double amount,
    required double newBalance,
    required String paymentMethod,
    String? bankName,
    required String bankAccNo,
  }) async {
    final payoutId = 'PO${DateTime.now().millisecondsSinceEpoch}';

    await _supabase
        .from('driver_profiles')
        .update({
      'available_balance': newBalance,
      'updated_at': DateTime.now().toIso8601String(),
    })
        .eq('user_id', userId);

    await _supabase.from('payout_history').insert({
      'id': payoutId,
      'user_id': userId,
      'amount': amount,
      'payout_at': DateTime.now().toIso8601String(),
      'payment_method': paymentMethod,
      'bank_name': bankName,
      'bank_acc_no': bankAccNo,
      'status': 'pending',
      'requested_at': DateTime.now().toIso8601String(),
    });

    return payoutId;
  }

// payout history
  Future<List<Map<String, dynamic>>> fetchPayoutHistory(String userId) async {
    final response = await _supabase
        .from('payout_history')
        .select()
        .eq('user_id', userId)
        .order('requested_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }


  Future<void> updatePayoutStatus(String payoutId, String status) async {
    await _supabase.from('payout_history').update({'status': status}).eq('id', payoutId);
  }
}