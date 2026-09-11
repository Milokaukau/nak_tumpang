import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/payment.dart';

class PaymentSupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _table = 'payments';

  DateTime _addOneMonthClamped(DateTime d) {
    final year = d.month == 12 ? d.year + 1 : d.year;
    final month = d.month == 12 ? 1 : d.month + 1;
    final daysInTargetMonth = DateTime(year, month + 1, 0).day;
    final day = d.day > daysInTargetMonth ? daysInTargetMonth : d.day;
    return DateTime(year, month, day);
  }

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
    if (totalDays <= 60) return;

    final depositEndDate = startDate.add(const Duration(days: 59));
    if (depositEndDate.isAfter(endDate)) return;

    final today = DateTime.now();
    DateTime cycleStart = depositEndDate.add(const Duration(days: 1));

    while (!cycleStart.isAfter(endDate)) {
      DateTime cycleEnd = _addOneMonthClamped(cycleStart).subtract(const Duration(days: 1));
      if (cycleEnd.isAfter(endDate)) {
        cycleEnd = endDate;
      }

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

  // =========================================================================
  // CANCELLATION BILLING LOGIC
  // =========================================================================

  /// Calculates the exact cancellation fee based on ACTUAL fetched days.
  /// Core Requirement: Fee = Fee Per Day × Actual Fetched Days.
  /// Completely ignores total subscription days to prevent overcharging.
  Future<Map<String, dynamic>> calculateCancellationFee(String subscriptionId) async {
    final sub = await _supabase
        .from('tumpang_subscription')
        .select('fee, deposit')
        .eq('id', subscriptionId)
        .maybeSingle();

    if (sub == null) throw Exception('Subscription not found');

    final dailyFee = double.tryParse(sub['fee']?.toString() ?? '') ?? 0.0;
    final deposit = double.tryParse(sub['deposit']?.toString() ?? '') ?? 0.0;

    // 1. Determine actual fetched/used days by strictly counting completed trip logs
    final logs = await _supabase
        .from('tumpang_trip_log')
        .select('id')
        .eq('tumpang_subscription_id', subscriptionId)
        .eq('status', 'completed');

    final int actualFetchedDays = (logs as List).length;

    // 2. Core Calculation: feePerDay × actualFetchedDays (Handles 0, 1, or N days naturally)
    final double totalIncurredFee = dailyFee * actualFetchedDays;

    // 3. Calculate already paid amounts (Deposit + any paid monthly invoices)
    final paidInvoices = await _supabase
        .from(_table)
        .select('amount')
        .eq('tumpang_subscription_id', subscriptionId)
        .not('paid_at', 'is', null);

    double totalPaidSoFar = deposit;
    for (final row in (paidInvoices as List)) {
      totalPaidSoFar += double.tryParse(row['amount']?.toString() ?? '') ?? 0.0;
    }

    // 4. Calculate final payable amount
    // Positive means passenger owes money for trips not covered by the deposit.
    // Negative means passenger is owed a refund.
    final double payableAmount = totalIncurredFee - totalPaidSoFar;

    return {
      'dailyFee': dailyFee,
      'actualFetchedDays': actualFetchedDays,
      'totalIncurredFee': totalIncurredFee,
      'totalPaidSoFar': totalPaidSoFar,
      'payableAmount': payableAmount,
    };
  }

  /// Generates the final cancellation bill based ONLY on the actual fetched days logic.
  Future<void> generateCancellationInvoice(String subscriptionId) async {
    final summary = await calculateCancellationFee(subscriptionId);
    final payableAmount = summary['payableAmount'] as double;

    // Only generate a new invoice if there's a positive amount owed
    if (payableAmount > 0) {
      final now = DateTime.now();
      final todayStr = now.toIso8601String().split('T').first;
      final paymentId = 'pay_${now.millisecondsSinceEpoch}_cancel';

      await _supabase.from(_table).insert({
        'id': paymentId,
        'tumpang_subscription_id': subscriptionId,
        'month': now.month,
        'year': now.year,
        // Cancellation bills are due immediately to settle the account
        'due_date': now.toIso8601String(),
        'paid_at': null,
        'amount': payableAmount, // Enforces the pure "actual fetched days" math
        'cycle_start_date': todayStr,
        'cycle_end_date': todayStr,
      });
    }
  }
}