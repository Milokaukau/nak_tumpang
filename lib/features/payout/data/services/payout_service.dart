import 'package:supabase_flutter/supabase_flutter.dart';

// data access to wallet
class PayoutService {
  final _supabase = Supabase.instance.client;


  Future<Map<String, dynamic>?> fetchDriverProfile(String userId) {
    return _supabase.from('driver_profiles').select().eq('user_id', userId).maybeSingle();
  }

  /// Reads the same fee value request_payout() applies server-side, so
  /// the app's pre-submission preview and the actual charged fee can
  /// never drift apart — there's exactly one place (payout_settings)
  /// that sets the number. Falls back to RM1 only if that row is
  /// somehow missing (matches payout_settings' own DEFAULT, so the
  /// preview still shows something sane rather than erroring out).
  Future<double> fetchBankTransferFee() async {
    final row = await _supabase.from('payout_settings').select('bank_transfer_fee').maybeSingle();
    return (row?['bank_transfer_fee'] as num?)?.toDouble() ?? 1.00;
  }

  /// Completed trips within [start, end) only — used for the "this
  /// month" stat cards. Filtered server-side by date range instead of
  /// fetching every completed trip a driver has ever done and summing
  /// client-side, so this stays cheap no matter how long the driver's
  /// been active (same reasoning as payout_history's paginated fetch).
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

  /// The [limit] most recent completed trips — used for the "Recent
  /// trips" list. Capped server-side with `.limit()` rather than
  /// fetching the driver's whole history and only using the first 10
  /// client-side.
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
  // populated for the same row regardless of what the client sends.
  //
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
  /// Every requested_at timestamp for this driver, nothing else — used
  /// only to compute which years/months have payouts in them for the
  /// History tab's filter chips. Deliberately not `select('*')`: this
  /// stays cheap even for a driver with years of history, since it's
  /// just one narrow timestamp column per row rather than the full
  /// bank_name/bank_acc_no/status/etc payload.
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

  /// One page of full payout rows, newest first, optionally scoped to a
  /// specific year and/or year+month. The filtering happens here (in the
  /// query) rather than client-side, so selecting a year doesn't require
  /// ever having loaded the driver's whole history into memory first.
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


  /// Was previously a raw `.update()` on payout_history — that let any
  /// signed-in client set ANY payout row's status to anything, with only
  /// RLS (not present in this repo) standing between that and abuse.
  /// Now goes through `set_payout_status`, a SECURITY DEFINER function
  /// (see sql/payout_status_rpc.sql) that checks the payout belongs to
  /// the caller and is still 'pending' before writing — the same
  /// server-enforced pattern request_payout() already uses for the
  /// balance/fee side.
  Future<void> updatePayoutStatus(String payoutId, String status) async {
    await _supabase.rpc('set_payout_status', params: {
      'p_payout_id': payoutId,
      'p_status': status,
    });
  }
}