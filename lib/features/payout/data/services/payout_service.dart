import 'package:supabase_flutter/supabase_flutter.dart';

class PayoutService {
  final _supabase = Supabase.instance.client;


  Future<Map<String, dynamic>?> fetchDriverProfile(String userId) {
    return _supabase.from('driver_profiles').select().eq('user_id', userId).maybeSingle();
  }

  Future<double> fetchBankTransferFee() async {
    final row = await _supabase.from('payout_settings').select('bank_transfer_fee').maybeSingle();
    return (row?['bank_transfer_fee'] as num?)?.toDouble() ?? 1.00;
  }

  Future<List<Map<String, dynamic>>> fetchCompletedTripsInRange(
      String userId, {
        required DateTime start,
        required DateTime end,
      }) async {
    final response = await _supabase
        .from('payments')
        .select('id, driver_net_amount, paid_at, tumpang_subscription!inner(driver_trips!inner(user_id))')
        .eq('tumpang_subscription.driver_trips.user_id', userId)
        .eq('payment_type', 'monthly')
        .gte('paid_at', start.toIso8601String())
        .lt('paid_at', end.toIso8601String())
        .not('credited_to_driver_at', 'is', null)
        .not('driver_net_amount', 'is', null);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> fetchRecentCompletedTrips(
      String userId, {
        int limit = 10,
      }) async {
    final response = await _supabase
        .from('payments')
        .select('''
          id,
          amount,
          platform_fee,
          driver_net_amount,
          cycle_start_date,
          cycle_end_date,
          paid_at,
          tumpang_subscription!inner(
            pickup_location,
            dropoff_location,
            fee,
            driver_trips!inner(user_id, trip_name),
            passenger_trips(user_id, users(name))
          )
        ''')
        .eq('tumpang_subscription.driver_trips.user_id', userId)
        .eq('payment_type', 'monthly')
        .not('credited_to_driver_at', 'is', null)
        .not('driver_net_amount', 'is', null)
        .order('paid_at', ascending: false)
        .limit(limit);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> requestPayout({
    required double amount,
    required String paymentMethod,
    String? bankName,
    String? bankAccNo,
    String? ewalletPhone,
  }) async {
    final result = await _supabase.rpc('request_payout', params: {
      'p_amount': amount,
      'p_payment_method': paymentMethod,
      'p_bank_name': bankName,
      'p_bank_acc_no': bankAccNo,
      'p_ewallet_phone': ewalletPhone,
    });

    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<DateTime>> fetchPayoutHistoryDates(String userId) async {
    final response = await _supabase
        .from('payout_history')
        .select('requested_at')
        .eq('user_id', userId)
        .not('requested_at', 'is', null);

    return List<Map<String, dynamic>>.from(response)
        .map((row) => DateTime.parse(row['requested_at'] as String))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchPayoutHistoryPage(
      String userId, {
        required int limit,
        required int offset,
        int? year,
        int? month,
      }) async {
    var query = _supabase.from('payout_history').select().eq('user_id', userId);

    if (year != null) {
      final startMonth = month ?? 1;
      final endMonth = month ?? 12;
      final start = DateTime(year, startMonth, 1);
      final end = DateTime(endMonth == 12 ? year + 1 : year, endMonth == 12 ? 1 : endMonth + 1, 1);
      query = query.gte('requested_at', start.toIso8601String()).lt('requested_at', end.toIso8601String());
    }

    final response = await query.order('requested_at', ascending: false).range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(response);
  }


  Future<void> updatePayoutStatus(String payoutId, String status) async {
    await _supabase.rpc('set_payout_status', params: {
      'p_payout_id': payoutId,
      'p_status': status,
    });
  }
}