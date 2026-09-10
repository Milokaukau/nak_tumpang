import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/payment.dart';

class PaymentSupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _table = 'payments';

  /// Adds one calendar month, clamping the day (e.g. 31 Jan -> 28/29 Feb) —
  /// same convention used elsewhere in the app (date range picker, etc.).
  DateTime _addOneMonthClamped(DateTime d) {
    final year = d.month == 12 ? d.year + 1 : d.year;
    final month = d.month == 12 ? 1 : d.month + 1;
    final daysInTargetMonth = DateTime(year, month + 1, 0).day;
    final day = d.day > daysInTargetMonth ? daysInTargetMonth : d.day;
    return DateTime(year, month, day);
  }

  /// Generates any billing-cycle invoices that are now due for a
  /// subscription longer than 60 days, and inserts them if missing.
  /// Safe to call repeatedly (idempotent) — checks cycle_start_date before
  /// inserting, so it never creates a duplicate invoice for the same cycle.
  ///
  /// Rules implemented:
  /// - First ~60 days are covered by the deposit already paid at signup —
  ///   no invoice generated for that period.
  /// - After that, invoices are generated in ~1-month cycles.
  /// - The last cycle truncates early if it would run past the
  ///   subscription's actual end date.
  /// - A cycle's invoice is only generated once its end date has been
  ///   reached (not generated in advance).
  /// - Invoice amount = dailyFee * (days in cycle - days covered by a
  ///   tumpang_exception row, from either driver or passenger, within
  ///   that cycle).
  /// - Due date = Snaps to the 1st of the following month.
  Future<void> generateDueInvoicesForSubscription(String subscriptionId) async {
    final sub = await _supabase
        .from('tumpang_subscription')
        .select('subscription_start_date, subscription_end_date, fee')
        .eq('id', subscriptionId)
        .maybeSingle();

    if (sub == null) return;

    final startDate = DateTime.tryParse(sub['subscription_start_date']?.toString() ?? '');
    final endDate = DateTime.tryParse(sub['subscription_end_date']?.toString() ?? '');
    final dailyFee = double.tryParse(sub['fee']?.toString() ?? '') ?? 0.0;
    if (startDate == null || endDate == null) return;

    final totalDays = endDate.difference(startDate).inDays + 1;
    if (totalDays <= 60) return; // fully covered by deposit, no invoices ever needed

    // Deposit covers the first min(totalDays, 60) days.
    final depositEndDate = startDate.add(const Duration(days: 59)); // 60 days inclusive from start
    if (depositEndDate.isAfter(endDate)) return; // shouldn't happen given totalDays > 60 check above

    final today = DateTime.now();
    DateTime cycleStart = depositEndDate.add(const Duration(days: 1));

    while (!cycleStart.isAfter(endDate)) {
      DateTime cycleEnd = _addOneMonthClamped(cycleStart).subtract(const Duration(days: 1));
      if (cycleEnd.isAfter(endDate)) {
        cycleEnd = endDate; // truncate final partial cycle to subscription end
      }

      // Only generate once the cycle has actually ended.
      if (!cycleEnd.isAfter(today)) {
        final cycleStartStr = cycleStart.toIso8601String().split('T').first;
        final cycleEndStr = cycleEnd.toIso8601String().split('T').first;

        final existing = await _supabase
            .from(_table)
            .select('id')
            .eq('tumpang_subscription_id', subscriptionId)
            .eq('cycle_start_date', cycleStartStr)
            .maybeSingle();

        if (existing == null) {
          final cycleDays = cycleEnd.difference(cycleStart).inDays + 1;

          // tumpang_exception stores DATE RANGES (start_date -> end_date),
          // from either the driver or the passenger, for any reason no
          // ride happened. Fetch every exception that overlaps this cycle
          // at all, then union the actual overlapping days into a set so
          // overlapping exception rows don't get double-counted.
          final exceptions = await _supabase
              .from('tumpang_exception')
              .select('start_date, end_date')
              .eq('tumpang_subscription_id', subscriptionId)
              .lte('start_date', cycleEndStr)
              .gte('end_date', cycleStartStr);

          final missedDates = <String>{};
          for (final row in (exceptions as List)) {
            final excStart = DateTime.parse(row['start_date'].toString());
            final excEnd = DateTime.parse(row['end_date'].toString());
            final overlapStart = excStart.isBefore(cycleStart) ? cycleStart : excStart;
            final overlapEnd = excEnd.isAfter(cycleEnd) ? cycleEnd : excEnd;
            for (DateTime d = overlapStart; !d.isAfter(overlapEnd); d = d.add(const Duration(days: 1))) {
              missedDates.add(d.toIso8601String().split('T').first);
            }
          }
          final missedDays = missedDates.length;

          final billableDays = (cycleDays - missedDays).clamp(0, cycleDays);
          final amount = dailyFee * billableDays;

          // --- NEW BILLING LOGIC: Snap to 1st of next month ---
          final dueDate = DateTime(cycleEnd.year, cycleEnd.month + 1, 1);

          final paymentId = 'pay_${DateTime.now().millisecondsSinceEpoch}_${cycleStartStr.replaceAll('-', '')}';

          await _supabase.from(_table).insert({
            'id': paymentId,
            'tumpang_subscription_id': subscriptionId,
            'cycle_start_date': cycleStartStr,
            'cycle_end_date': cycleEndStr,
            'month': cycleEnd.month,
            'year': cycleEnd.year,
            'due_date': dueDate.toIso8601String(),
            'paid_at': null,
            'amount': amount,
          });
        }
      }

      cycleStart = cycleEnd.add(const Duration(days: 1));
    }
  }

  /// Runs invoice generation across every active subscription belonging to
  /// this passenger, before fetching the payment lists. Failures for one
  /// subscription don't block the others.
  Future<void> generateDueInvoicesForUser(String userId) async {
    try {
      final userTrips = await _supabase
          .from('passenger_trips')
          .select('id')
          .eq('user_id', userId);
      final tripIds = (userTrips as List).map((t) => t['id'] as String).toList();
      if (tripIds.isEmpty) return;

      final subs = await _supabase
          .from('tumpang_subscription')
          .select('id')
          .inFilter('passenger_trip_id', tripIds)
          .eq('status', 'active');
      final subIds = (subs as List).map((s) => s['id'] as String).toList();

      for (final subId in subIds) {
        try {
          await generateDueInvoicesForSubscription(subId);
        } catch (e) {
          debugPrint('Error generating invoices for subscription $subId: $e');
        }
      }
    } catch (e) {
      debugPrint('Error running invoice generation: $e');
    }
  }

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