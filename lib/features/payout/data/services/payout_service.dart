import 'package:supabase_flutter/supabase_flutter.dart';

// data access to wallet
class PayoutService {
  final _supabase = Supabase.instance.client;


  Future<Map<String, dynamic>?> fetchDriverProfile(String userId) {
    return _supabase.from('driver_profiles').select().eq('user_id', userId).maybeSingle();
  }

  // reads the fee value in payout_settings
  // falls back to 1rm if that row is missing
  Future<double> fetchBankTransferFee() async {
    final row = await _supabase.from('payout_settings').select('bank_transfer_fee').maybeSingle();
    return (row?['bank_transfer_fee'] as num?)?.toDouble() ?? 1.00;
  }

  // filtered server-side by date range (not full)
  Future<List<Map<String, dynamic>>> fetchCompletedTripsInRange(
      String userId, {
        required DateTime start,
        required DateTime end,
      }) async {
    final response = await _supabase
        .from('tumpang_request')
        .select('id, fee, sub_start_date, driver_trips!inner(user_id)')
        .eq('driver_trips.user_id', userId)
        .eq('status', 'completed')
        .gte('sub_start_date', start.toIso8601String())
        .lt('sub_start_date', end.toIso8601String());

    return List<Map<String, dynamic>>.from(response);
  }

  // capped server-side with .limit() rather than fetching whole history and only using the first 10 client-side
  Future<List<Map<String, dynamic>>> fetchRecentCompletedTrips(
      String userId, {
        int limit = 10,
      }) async {
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
        .order('sub_start_date', ascending: false)
        .limit(limit);

    return List<Map<String, dynamic>>.from(response);
  }

  // e-wallet payment method will have null bank name/bank_acc_no;
  // bank_transfer will have null ewallet_phone. request_payout()
  // enforces this pairing server-side too, so the two never end up
  // populated for the same row regardless of what the client sends

  // Runs as one atomic call via the `request_payout` Postgres function
  // (see request_payout.sql) — the balance deduction and the
  // payout_history insert happen in a single transaction on the server,
  // so an interruption between them can't leave the two out of sync the
  // way two separate client calls could.
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

// payout history
  // every requested_at timestamp for this driver
  // compute which years and month payout in them for the filter chips in History tab

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

  // one page of all payout rows, sorted by newest
  // can be scoped to specific year and month
  // filtering happens here so selecting year don't require driver's whole memory being loaded in memory
  Future<List<Map<String, dynamic>>> fetchPayoutHistoryPage(
      String userId, {
        required int limit,
        required int offset,
        int? year,
        int? month, // 1-12; only meaningful together with `year`
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


  // check if the payout belongs to caller
  // set payout status to needed status currently
  // mock status
  Future<void> updatePayoutStatus(String payoutId, String status) async {
    await _supabase.rpc('set_payout_status', params: {
      'p_payout_id': payoutId,
      'p_status': status,
    });
  }
}