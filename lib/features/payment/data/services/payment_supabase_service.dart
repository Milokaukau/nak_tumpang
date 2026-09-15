import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/payment.dart';

/// Bundles the pending payments returned from Supabase together with the
/// ids of any "zombie" invoice rows (premature bills, or bills recalculated
/// down to zero) that [PaymentSupabaseService.recalculateUnpaidInvoices]
/// deleted server-side while building the list. Callers (PaymentViewModel)
/// use [deletedInvoiceIds] to purge the same rows from the offline SQLite
/// cache so they don't resurface next time the app opens without network.
class PendingPaymentsResult {
  final List<Payment> payments;
  final List<String> deletedInvoiceIds;

  const PendingPaymentsResult({
    required this.payments,
    required this.deletedInvoiceIds,
  });
}

class PaymentSupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _table = 'payments';

  // Helper to safely advance the calendar date to midnight, avoiding 24-hour DST traps
  DateTime _nextCalendarDate(DateTime date) =>
      DateTime(date.year, date.month, date.day + 1);

  // Inclusive calendar-day count between two dates, computed via UTC-normalized
  // date-only values so a DST transition between start and end can't shave a
  // day off an elapsed-hours-based difference().inDays calculation.
  int _inclusiveCalendarDays(DateTime start, DateTime end) =>
      DateTime.utc(end.year, end.month, end.day)
          .difference(DateTime.utc(start.year, start.month, start.day))
          .inDays +
          1;

  // Advance a date by a fixed number of CALENDAR days (not 24-hour periods),
  // so a DST transition crossed along the way can't push the result onto the
  // wrong side of a calendar date.
  DateTime _addCalendarDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  Future<Map<String, dynamic>> fetchProformaInvoiceDetails({
    required String subscriptionId,
    DateTime? cycleStart,
    DateTime? cycleEnd,
  }) async {
    final sub = await _supabase
        .from('tumpang_subscription')
        .select('fee, passenger_trip_id, driver_trip_id')
        .eq('id', subscriptionId)
        .maybeSingle();
    if (sub == null) throw StateError('Subscription not found.');

    final passengerTripId = sub['passenger_trip_id']?.toString();
    final driverTripId = sub['driver_trip_id']?.toString();
    final passengerTrip = passengerTripId == null
        ? null
        : await _supabase
        .from('passenger_trips')
        .select('trip_name, active_monday, active_tuesday, active_wednesday, active_thursday, active_friday, active_saturday, active_sunday')
        .eq('id', passengerTripId)
        .maybeSingle();
    final driverTrip = driverTripId == null
        ? null
        : await _supabase.from('driver_trips').select('trip_name').eq('id', driverTripId).maybeSingle();

    List<dynamic> exceptions = [];
    if (cycleStart != null && cycleEnd != null) {
      exceptions = await _supabase
          .from('tumpang_exception')
          .select('start_date, end_date, reason')
          .eq('tumpang_subscription_id', subscriptionId)
          .eq('initiated_by_role', 'driver')
          .lte('start_date', cycleEnd.toIso8601String().split('T').first)
          .gte('end_date', cycleStart.toIso8601String().split('T').first);
    }

    return {
      'dailyFee': double.tryParse(sub['fee']?.toString() ?? '') ?? 0.0,
      'passengerTripName': passengerTrip?['trip_name']?.toString(),
      'driverTripName': driverTrip?['trip_name']?.toString(),
      'schedule': passengerTrip ?? <String, dynamic>{},
      'exceptions': exceptions,
    };
  }

  bool _isDayActive(DateTime date, Map<String, dynamic> schedule) {
    switch (date.weekday) {
      case 1: return schedule['active_monday'] == true;
      case 2: return schedule['active_tuesday'] == true;
      case 3: return schedule['active_wednesday'] == true;
      case 4: return schedule['active_thursday'] == true;
      case 5: return schedule['active_friday'] == true;
      case 6: return schedule['active_saturday'] == true;
      case 7: return schedule['active_sunday'] == true;
      default: return false;
    }
  }

  Future<int> _countDriverMissedDays(
      String subscriptionId,
      DateTime cycleStart,
      DateTime cycleEnd,
      Map<String, dynamic> schedule,
      ) async {
    final cycleStartStr = cycleStart.toIso8601String().split('T').first;
    final cycleEndStr = cycleEnd.toIso8601String().split('T').first;

    final exceptions = await _supabase
        .from('tumpang_exception')
        .select('start_date, end_date')
        .eq('tumpang_subscription_id', subscriptionId)
        .eq('initiated_by_role', 'driver')
        .lte('start_date', cycleEndStr)
        .gte('end_date', cycleStartStr);

    final missedDates = <String>{};
    for (final row in (exceptions as List)) {
      final excStart = DateTime.parse(row['start_date'].toString());
      final excEnd = DateTime.parse(row['end_date'].toString());
      final overlapStart = excStart.isBefore(cycleStart) ? cycleStart : excStart;
      final overlapEnd = excEnd.isAfter(cycleEnd) ? cycleEnd : excEnd;
      for (DateTime d = overlapStart; !d.isAfter(overlapEnd); d = _nextCalendarDate(d)) {
        if (_isDayActive(d, schedule)) {
          missedDates.add(d.toIso8601String().split('T').first);
        }
      }
    }
    return missedDates.length;
  }

  Future<void> generateDueInvoicesForSubscription(String subscriptionId) async {
    final sub = await _supabase
        .from('tumpang_subscription')
        .select('subscription_start_date, subscription_end_date, fee, passenger_trip_id')
        .eq('id', subscriptionId)
        .maybeSingle();

    if (sub == null) return;

    final startDate = DateTime.tryParse(sub['subscription_start_date']?.toString() ?? '');
    final endDate = DateTime.tryParse(sub['subscription_end_date']?.toString() ?? '');
    final dailyFee = double.tryParse(sub['fee']?.toString() ?? '') ?? 0.0;
    if (startDate == null || endDate == null) return;

    final passengerTripId = sub['passenger_trip_id']?.toString();
    if (passengerTripId == null) return;
    final schedule = await _supabase
        .from('passenger_trips')
        .select('active_monday, active_tuesday, active_wednesday, active_thursday, active_friday, active_saturday, active_sunday')
        .eq('id', passengerTripId)
        .maybeSingle();
    if (schedule == null) return;

    final totalDays = _inclusiveCalendarDays(startDate, endDate);
    if (totalDays <= 60) return;

    final depositEndDate = _addCalendarDays(startDate, 59);
    if (depositEndDate.isAfter(endDate)) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime cycleStart = _nextCalendarDate(depositEndDate);

    while (!cycleStart.isAfter(endDate)) {
      DateTime cycleEnd = _addCalendarDays(cycleStart, 29);

      if (cycleEnd.isAfter(endDate)) {
        cycleEnd = endDate;
      }

      DateTime nextCycleStart = _nextCalendarDate(cycleEnd);

      // Billing date is ALWAYS cycle end date + 1 day
      final billingDate = _nextCalendarDate(cycleEnd);

      // ONLY generate the invoice if today has reached the billing date
      if (!today.isBefore(billingDate)) {
        final cycleStartStr = cycleStart.toIso8601String().split('T').first;
        final cycleEndStr = cycleEnd.toIso8601String().split('T').first;

        final existingOverlap = await _supabase
            .from(_table)
            .select('id, cycle_start_date, cycle_end_date')
            .eq('tumpang_subscription_id', subscriptionId)
            .lte('cycle_start_date', cycleEndStr)
            .gte('cycle_end_date', cycleStartStr);

        if ((existingOverlap as List).isNotEmpty) {
          for (final row in existingOverlap) {
            final existingEnd = DateTime.tryParse(row['cycle_end_date']?.toString() ?? '');
            if (existingEnd != null) {
              final afterExisting = _nextCalendarDate(existingEnd);
              if (afterExisting.isAfter(nextCycleStart)) {
                nextCycleStart = afterExisting;
              }
            }
          }
        } else {
          var activeCycleDays = 0;
          for (var date = cycleStart; !date.isAfter(cycleEnd); date = _nextCalendarDate(date)) {
            if (_isDayActive(date, schedule)) activeCycleDays++;
          }
          final missedDays = await _countDriverMissedDays(subscriptionId, cycleStart, cycleEnd, schedule);
          final billableDays = (activeCycleDays - missedDays).clamp(0, activeCycleDays);
          final amount = dailyFee * billableDays;

          if (amount > 0) {
            // Due date is ALWAYS fixed to the 1st of the next month following billing date
            final dueDate = DateTime(billingDate.year, billingDate.month + 1, 1);
            final paymentId = 'pay_${DateTime.now().millisecondsSinceEpoch}_${cycleStartStr.replaceAll('-', '')}';

            await _supabase.from(_table).insert({
              'id': paymentId,
              'tumpang_subscription_id': subscriptionId,
              'cycle_start_date': cycleStartStr,
              'cycle_end_date': cycleEndStr,
              'month': billingDate.month,
              'year': billingDate.year,
              'due_date': dueDate.toIso8601String(),
              'paid_at': null,
              'amount': amount,
              'payment_type': 'monthly',
            });
          }
        }
      }
      cycleStart = nextCycleStart;
    }
  }

  Future<List<String>> recalculateUnpaidInvoices(List<Map<String, dynamic>> unpaidPaymentRows) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final deletedIds = <String>[];

    for (final row in unpaidPaymentRows) {
      try {
        final paymentId = row['id']?.toString();
        final subscriptionId = row['tumpang_subscription_id']?.toString();

        if (paymentId == null || paymentId.endsWith('_cancel') || subscriptionId == null) {
          continue;
        }

        final cycleStartStr = row['cycle_start_date']?.toString();
        final cycleEndStr = row['cycle_end_date']?.toString();

        DateTime? cycleStart;
        DateTime? cycleEnd;

        if (cycleStartStr != null && cycleEndStr != null) {
          cycleStart = DateTime.tryParse(cycleStartStr);
          cycleEnd = DateTime.tryParse(cycleEndStr);
        }

        // 1. HIDE PREMATURE BILLS — LOCAL UI CORRECTED FIRST.
        // Billing Date = cycle_end_date + 1 day. If sysdate hasn't reached
        // it yet, this row must never be visible. The in-memory row is
        // zeroed out immediately so the screen is correct even if the
        // Supabase delete below fails (offline, RLS, network blip, etc).
        if (cycleEnd != null) {
          final billingDate = _nextCalendarDate(cycleEnd);

          if (today.isBefore(billingDate)) {
            row['amount'] = 0.0;
            deletedIds.add(paymentId);

            // Best-effort remote + local-SQLite cleanup. UI correctness
            // does not depend on this succeeding.
            try {
              await _supabase.from(_table).delete().eq('id', paymentId).isFilter('paid_at', null);
            } catch (e) {
              debugPrint('Could not delete premature invoice $paymentId from Supabase (UI already hidden): $e');
            }
            continue;
          }
        }

        // 2. FIX DUE DATE / MONTH / YEAR — LOCAL UI CORRECTED FIRST.
        // Due Date is ALWAYS the 1st of the month after the Billing Date's
        // month. No exceptions. Falls back to the saved month/year for
        // legacy rows missing cycle_start_date/cycle_end_date.
        int expectedMonth;
        int expectedYear;

        if (cycleEnd != null) {
          final billingDate = _nextCalendarDate(cycleEnd);
          expectedMonth = billingDate.month;
          expectedYear = billingDate.year;
        } else {
          expectedMonth = int.tryParse(row['month']?.toString() ?? '') ?? today.month;
          expectedYear = int.tryParse(row['year']?.toString() ?? '') ?? today.year;
        }
        // DateTime normalizes month 13 into January of the next year, so
        // this also correctly handles a December billing date.
        final expectedDueDate = DateTime(expectedYear, expectedMonth + 1, 1);
        final expectedDueDateStr = expectedDueDate.toIso8601String();

        final updates = <String, dynamic>{};

        final currentDueDateStr = row['due_date']?.toString();
        if (currentDueDateStr == null || !currentDueDateStr.startsWith(expectedDueDateStr.split('T').first)) {
          row['due_date'] = expectedDueDateStr; // local first
          updates['due_date'] = expectedDueDateStr;
        }

        final currentMonth = int.tryParse(row['month']?.toString() ?? '');
        if (currentMonth != expectedMonth) {
          row['month'] = expectedMonth; // local first
          updates['month'] = expectedMonth;
        }

        final currentYear = int.tryParse(row['year']?.toString() ?? '');
        if (currentYear != expectedYear) {
          row['year'] = expectedYear; // local first
          updates['year'] = expectedYear;
        }

        // 3. RECALCULATE AMOUNT — LOCAL UI CORRECTED FIRST.
        if (cycleStart != null && cycleEnd != null) {
          final sub = await _supabase
              .from('tumpang_subscription')
              .select('fee, passenger_trip_id')
              .eq('id', subscriptionId)
              .maybeSingle();

          final passengerTripId = sub?['passenger_trip_id']?.toString();
          if (passengerTripId != null) {
            final schedule = await _supabase
                .from('passenger_trips')
                .select('active_monday, active_tuesday, active_wednesday, active_thursday, active_friday, active_saturday, active_sunday')
                .eq('id', passengerTripId)
                .maybeSingle();

            if (schedule != null) {
              final dailyFee = double.tryParse(sub?['fee']?.toString() ?? '') ?? 0.0;
              var activeCycleDays = 0;
              for (var date = cycleStart; !date.isAfter(cycleEnd); date = _nextCalendarDate(date)) {
                if (_isDayActive(date, schedule)) activeCycleDays++;
              }
              final missedDays = await _countDriverMissedDays(subscriptionId, cycleStart, cycleEnd, schedule);
              final billableDays = (activeCycleDays - missedDays).clamp(0, activeCycleDays);
              final correctAmount = dailyFee * billableDays;

              if (correctAmount <= 0) {
                row['amount'] = 0.0; // local first
                deletedIds.add(paymentId);
                try {
                  await _supabase.from(_table).delete().eq('id', paymentId).isFilter('paid_at', null);
                } catch (e) {
                  debugPrint('Could not delete zeroed-out invoice $paymentId from Supabase (UI already hidden): $e');
                }
                continue;
              }

              final currentAmount = double.tryParse(row['amount']?.toString() ?? '') ?? 0.0;
              if ((correctAmount - currentAmount).abs() > 0.005) {
                row['amount'] = correctAmount; // local first
                updates['amount'] = correctAmount;
              }
            }
          }
        }

        // 4. PERSIST TO SUPABASE, BEST-EFFORT.
        // The local row (and thus the UI) is already correct as of steps
        // 1–3 above. A failure here only means the fix hasn't reached the
        // remote source of truth yet — it'll be retried on the next
        // refresh — but it must never roll back what's already shown.
        if (updates.isNotEmpty) {
          try {
            await _supabase.from(_table).update(updates).eq('id', paymentId).isFilter('paid_at', null);
          } catch (e) {
            debugPrint('Could not persist invoice correction for $paymentId to Supabase (UI already corrected): $e');
          }
        }
      } catch (e) {
        debugPrint('Error recalculating invoice ${row['id']}: $e');
      }
    }

    return deletedIds;
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

  Future<PendingPaymentsResult> fetchPendingPayments(String userId) async {
    try {
      final userTrips = await _supabase
          .from('passenger_trips')
          .select('id')
          .eq('user_id', userId);

      final tripIds = (userTrips as List).map((t) => t['id'] as String).toList();
      if (tripIds.isEmpty) return const PendingPaymentsResult(payments: [], deletedInvoiceIds: []);

      final subs = await _supabase
          .from('tumpang_subscription')
          .select('id')
          .inFilter('passenger_trip_id', tripIds);

      final subIds = (subs as List).map((s) => s['id'] as String).toList();
      if (subIds.isEmpty) return const PendingPaymentsResult(payments: [], deletedInvoiceIds: []);

      final List<dynamic> response = await _supabase
          .from(_table)
          .select('*, tumpang_subscription(pickup_location, dropoff_location)')
          .inFilter('tumpang_subscription_id', subIds)
          .isFilter('paid_at', null)
          .order('due_date', ascending: true);

      // Map copy so Dart allows local edits when hiding bills
      final rows = (response as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      // Cleans data & enforces strict UI corrections first, and reports back
      // any invoice ids it deleted remotely (premature or zeroed-out bills)
      // so the caller can keep the offline SQLite cache in sync.
      final deletedInvoiceIds = await recalculateUnpaidInvoices(rows);

      final payments = rows
          .where((row) => (double.tryParse(row['amount']?.toString() ?? '') ?? 0.0) > 0)
          .map(Payment.fromJson)
          .toList();

      return PendingPaymentsResult(payments: payments, deletedInvoiceIds: deletedInvoiceIds);
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

  // Was a raw `update paid_at`. Now routed through settle_payments() so
  // that marking a payment paid and crediting the responsible driver's
  // payout balance (net of the platform fee) happen atomically — see
  // supabase/migrations/settle_payments.sql.
  Future<void> completePaymentBatch(List<String> paymentIds) async {
    await _supabase.rpc('settle_payments', params: {'p_payment_ids': paymentIds});
  }

  // =========================================================================
  // CANCELLATION BILLING LOGIC
  // =========================================================================

  Future<Map<String, dynamic>> calculateCancellationFee(String subscriptionId) async {
    final sub = await _supabase
        .from('tumpang_subscription')
        .select('fee')
        .eq('id', subscriptionId)
        .maybeSingle();

    if (sub == null) throw Exception('Subscription not found');

    final dailyFee = double.tryParse(sub['fee']?.toString() ?? '') ?? 0.0;

    final logs = await _supabase
        .from('tumpang_trip_log')
        .select('id')
        .eq('tumpang_subscription_id', subscriptionId)
        .eq('status', 'completed');

    final int actualFetchedDays = (logs as List).length;
    final double totalIncurredFee = dailyFee * actualFetchedDays;

    final paidInvoices = await _supabase
        .from(_table)
        .select('amount')
        .eq('tumpang_subscription_id', subscriptionId)
        .not('paid_at', 'is', null);

    double totalPaidSoFar = 0.0;
    for (final row in (paidInvoices as List)) {
      totalPaidSoFar += double.tryParse(row['amount']?.toString() ?? '') ?? 0.0;
    }

    final double payableAmount = totalIncurredFee - totalPaidSoFar;

    return {
      'dailyFee': dailyFee,
      'actualFetchedDays': actualFetchedDays,
      'totalIncurredFee': totalIncurredFee,
      'totalPaidSoFar': totalPaidSoFar,
      'payableAmount': payableAmount,
    };
  }

  Future<void> generateCancellationInvoice(String subscriptionId) async {
    final existing = await _supabase
        .from(_table)
        .select('id')
        .eq('tumpang_subscription_id', subscriptionId)
        .like('id', '%_cancel')
        .maybeSingle();
    if (existing != null) return;

    final summary = await calculateCancellationFee(subscriptionId);
    final payableAmount = summary['payableAmount'] as double;

    final now = DateTime.now();
    final todayStr = now.toIso8601String().split('T').first;

    if (payableAmount > 0) {
      final paymentId = 'pay_${now.millisecondsSinceEpoch}_cancel';
      await _supabase.from(_table).insert({
        'id': paymentId,
        'tumpang_subscription_id': subscriptionId,
        'month': now.month,
        'year': now.year,
        'due_date': now.toIso8601String(),
        'paid_at': null,
        'amount': payableAmount,
        'cycle_start_date': todayStr,
        'cycle_end_date': todayStr,
        'payment_type': 'cancellation',
      });
    } else if (payableAmount < 0) {
      final refundId = 'pay_${now.millisecondsSinceEpoch}_refund';
      await _supabase.from(_table).insert({
        'id': refundId,
        'tumpang_subscription_id': subscriptionId,
        'month': now.month,
        'year': now.year,
        'due_date': now.toIso8601String(),
        'paid_at': now.toIso8601String(),
        'amount': payableAmount,
        'cycle_start_date': todayStr,
        'cycle_end_date': todayStr,
        'payment_type': 'refund',
      });
      await _supabase.from('tumpang_subscription')
          .update({'deposit_refunded': true})
          .eq('id', subscriptionId);
    }

    await _supabase
        .from(_table)
        .delete()
        .eq('tumpang_subscription_id', subscriptionId)
        .isFilter('paid_at', null)
        .not('id', 'like', '%_cancel');
  }
}