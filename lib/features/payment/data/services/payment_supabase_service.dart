import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/payment.dart';

class PaymentSupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _table = 'payments';

  /// Returns whether [date] is one of the passenger's scheduled ride days.
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

  /// Counts driver-caused missed days within [cycleStart]..[cycleEnd].
  /// Passenger-initiated exceptions ("no need fetch") are NOT deducted -
  /// only the driver failing to provide the ride reduces what's billed.
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
      for (DateTime d = overlapStart; !d.isAfter(overlapEnd); d = d.add(const Duration(days: 1))) {
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

    final totalDays = endDate.difference(startDate).inDays + 1;
    if (totalDays <= 60) return;

    final depositEndDate = startDate.add(const Duration(days: 59));
    if (depositEndDate.isAfter(endDate)) return;

    final today = DateTime.now();
    DateTime cycleStart = depositEndDate.add(const Duration(days: 1));

    while (!cycleStart.isAfter(endDate)) {
      DateTime cycleEnd = cycleStart.add(const Duration(days: 29));

      if (cycleEnd.isAfter(endDate)) {
        cycleEnd = endDate;
      }

      DateTime nextCycleStart = cycleEnd.add(const Duration(days: 1));

      if (!cycleStart.isAfter(today)) {
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
            if (existingEnd != null && existingEnd.add(const Duration(days: 1)).isAfter(nextCycleStart)) {
              nextCycleStart = existingEnd.add(const Duration(days: 1));
            }
          }
        } else {
          var activeCycleDays = 0;
          for (var date = cycleStart; !date.isAfter(cycleEnd); date = date.add(const Duration(days: 1))) {
            if (_isDayActive(date, schedule)) activeCycleDays++;
          }
          final missedDays = await _countDriverMissedDays(subscriptionId, cycleStart, cycleEnd, schedule);
          final billableDays = (activeCycleDays - missedDays).clamp(0, activeCycleDays);
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
      cycleStart = nextCycleStart;
    }
  }

  Future<void> recalculateUnpaidInvoices(List<Map<String, dynamic>> unpaidPaymentRows) async {
    for (final row in unpaidPaymentRows) {
      try {
        final paymentId = row['id']?.toString();
        final subscriptionId = row['tumpang_subscription_id']?.toString();
        final cycleStartStr = row['cycle_start_date']?.toString();
        final cycleEndStr = row['cycle_end_date']?.toString();
        if (paymentId == null || subscriptionId == null || cycleStartStr == null || cycleEndStr == null) {
          continue;
        }

        final cycleStart = DateTime.tryParse(cycleStartStr);
        final cycleEnd = DateTime.tryParse(cycleEndStr);
        if (cycleStart == null || cycleEnd == null) continue;

        final sub = await _supabase
            .from('tumpang_subscription')
            .select('fee, passenger_trip_id')
            .eq('id', subscriptionId)
            .maybeSingle();
        final dailyFee = double.tryParse(sub?['fee']?.toString() ?? '') ?? 0.0;
        final passengerTripId = sub?['passenger_trip_id']?.toString();
        if (passengerTripId == null) continue;
        final schedule = await _supabase
            .from('passenger_trips')
            .select('active_monday, active_tuesday, active_wednesday, active_thursday, active_friday, active_saturday, active_sunday')
            .eq('id', passengerTripId)
            .maybeSingle();
        if (schedule == null) continue;

        var activeCycleDays = 0;
        for (var date = cycleStart; !date.isAfter(cycleEnd); date = date.add(const Duration(days: 1))) {
          if (_isDayActive(date, schedule)) activeCycleDays++;
        }
        final missedDays = await _countDriverMissedDays(subscriptionId, cycleStart, cycleEnd, schedule);
        final billableDays = (activeCycleDays - missedDays).clamp(0, activeCycleDays);
        final correctAmount = dailyFee * billableDays;

        final currentAmount = double.tryParse(row['amount']?.toString() ?? '') ?? 0.0;
        if ((correctAmount - currentAmount).abs() > 0.005) {
          await _supabase.from(_table).update({'amount': correctAmount}).eq('id', paymentId);
          row['amount'] = correctAmount;
        }
      } catch (e) {
        debugPrint('Error recalculating invoice ${row['id']}: $e');
      }
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

      final rows = (response as List).cast<Map<String, dynamic>>();
      await recalculateUnpaidInvoices(rows);

      return rows.map((json) => Payment.fromJson(json)).toList();
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

  Future<Map<String, dynamic>> calculateCancellationFee(String subscriptionId) async {
    final sub = await _supabase
        .from('tumpang_subscription')
        .select('fee, deposit')
        .eq('id', subscriptionId)
        .maybeSingle();

    if (sub == null) throw Exception('Subscription not found');

    final dailyFee = double.tryParse(sub['fee']?.toString() ?? '') ?? 0.0;
    final deposit = double.tryParse(sub['deposit']?.toString() ?? '') ?? 0.0;

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

    double totalPaidSoFar = deposit;
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
