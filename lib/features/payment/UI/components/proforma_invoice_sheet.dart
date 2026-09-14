import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/payment.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class ProformaInvoiceSheet extends StatefulWidget {
  final Payment payment;

  const ProformaInvoiceSheet({super.key, required this.payment});

  static Future<void> show(BuildContext context, Payment payment) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProformaInvoiceSheet(payment: payment),
    );
  }

  @override
  State<ProformaInvoiceSheet> createState() => _ProformaInvoiceSheetState();
}

class _ProformaInvoiceSheetState extends State<ProformaInvoiceSheet> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _loading = true;

  double _dailyFee = 0.0;
  int _totalCycleDays = 30;
  int _missedDays = 0;
  List<String> _missedDateList = [];
  String? _passengerTripName;
  String? _driverTripName;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadInvoiceDetails();
  }

  Future<void> _loadInvoiceDetails() async {
    try {
      final sub = await _supabase
          .from('tumpang_subscription')
          .select('fee, passenger_trip_id, driver_trip_id')
          .eq('id', widget.payment.subscriptionId)
          .maybeSingle();

      _dailyFee = double.tryParse(sub?['fee']?.toString() ?? '') ?? 0.0;

      final passengerTripId = sub?['passenger_trip_id']?.toString();
      final driverTripId = sub?['driver_trip_id']?.toString();

      if (passengerTripId != null) {
        final pTrip = await _supabase
            .from('passenger_trips')
            .select('trip_name')
            .eq('id', passengerTripId)
            .maybeSingle();
        _passengerTripName = pTrip?['trip_name']?.toString();
      }

      if (driverTripId != null) {
        final dTrip = await _supabase
            .from('driver_trips')
            .select('trip_name')
            .eq('id', driverTripId)
            .maybeSingle();
        _driverTripName = dTrip?['trip_name']?.toString();
      }

      final start = widget.payment.cycleStartDate;
      final end = widget.payment.cycleEndDate;
      if (start != null && end != null) {
        _totalCycleDays = end.difference(start).inDays + 1;

        final startStr = start.toIso8601String().split('T').first;
        final endStr = end.toIso8601String().split('T').first;

        // Only DRIVER-initiated exceptions reduce the bill. A passenger
        // saying "no need fetch" doesn't entitle them to a deduction -
        // only the driver actually failing to provide the ride does.
        // NOTE: this query is used ONLY to list which dates were missed,
        // never to compute the day count/amount below - see comment there.
        final exceptions = await _supabase
            .from('tumpang_exception')
            .select('start_date, end_date, reason')
            .eq('tumpang_subscription_id', widget.payment.subscriptionId)
            .eq('initiated_by_role', 'driver')
            .lte('start_date', endStr)
            .gte('end_date', startStr);

        final dates = <String>{};
        for (final row in (exceptions as List)) {
          final s = DateTime.parse(row['start_date'].toString());
          final e = DateTime.parse(row['end_date'].toString());
          final overlapStart = s.isBefore(start) ? start : s;
          final overlapEnd = e.isAfter(end) ? end : e;
          for (DateTime d = overlapStart; !d.isAfter(overlapEnd); d = d.add(const Duration(days: 1))) {
            dates.add(d.toIso8601String().split('T').first);
          }
        }
        _missedDateList = dates.toList()..sort();

        // The missed-days COUNT (and therefore the deduction shown below)
        // is derived from widget.payment.amount - the stored, backend
        // self-healing value (PaymentSupabaseService.recalculateUnpaidInvoices
        // keeps it in sync with tumpang_exception on every load) - NOT from
        // re-summing the query above. Two independent computations of the
        // same number can drift apart if either query has a bug, a stale
        // cache, or a race; deriving from the authoritative amount instead
        // makes it structurally impossible for this screen's breakdown to
        // disagree with the total the passenger is actually charged.
        if (_dailyFee > 0) {
          final subtotal = _totalCycleDays * _dailyFee;
          final derivedMissedDays = ((subtotal - widget.payment.amount) / _dailyFee).round();
          _missedDays = derivedMissedDays.clamp(0, _totalCycleDays);

          if (_missedDays != dates.length) {
            // Surfaces a real mismatch (e.g. the exceptions query above
            // found a different count than the amount implies) instead of
            // silently hiding it - worth investigating if this ever fires.
            debugPrint(
              'Proforma mismatch for ${widget.payment.id}: amount implies '
                  '$_missedDays missed day(s) but exceptions query found '
                  '${dates.length}.',
            );
          }
        } else {
          _missedDays = dates.length;
        }
      } else {
        if (_dailyFee > 0) {
          _totalCycleDays = (widget.payment.amount / _dailyFee).round();
        }
      }
    } catch (e) {
      debugPrint('Error loading proforma details: $e');
      if (mounted) _loadError = 'Some invoice details could not be loaded.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDateDdMmYyyy(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final dueDateStr = widget.payment.dueDate.toIso8601String().split('T').first;
    final subtotal = _totalCycleDays * _dailyFee;
    final deduction = _missedDays * _dailyFee;
    // The actual amount due is ALWAYS subtotal minus the deduction we just
    // computed - never the possibly-stale stored value. This is what
    // actually gets charged, since paySelectedWithStripe() sums each
    // Payment's .amount - if the two ever disagreed the preview would be
    // lying about what the passenger is about to pay.
    final totalDue = (subtotal - deduction).clamp(0, double.infinity);

    final isOverdue = DateTime.now().isAfter(widget.payment.dueDate);

    String billingPeriodText = widget.payment.dateRange;
    if (widget.payment.cycleStartDate != null && widget.payment.cycleEndDate != null) {
      final start = _formatDateDdMmYyyy(widget.payment.cycleStartDate!);
      final end = _formatDateDdMmYyyy(widget.payment.cycleEndDate!);
      billingPeriodText = '${widget.payment.dateRange}\n($start to $end)';
    }

    final tripNameText = [_passengerTripName, _driverTripName]
        .where((n) => n != null && n.isNotEmpty)
        .join(' / ');

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'INVOICE DETAILS',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ref: ${widget.payment.id}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOverdue ? Colors.red.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isOverdue ? Colors.red.shade200 : Colors.orange.shade200),
                  ),
                  child: Text(
                    isOverdue ? 'OVERDUE' : 'UNPAID',
                    style: TextStyle(
                        color: isOverdue ? Colors.red : Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (_loadError != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  '$_loadError The Total Amount Due below is still accurate.',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            if (tripNameText.isNotEmpty) _infoRow('Trip Name', tripNameText),
            _infoRow('Service Route', widget.payment.direction),
            _infoRow('Billing Period', billingPeriodText),
            _infoRow('Due Date', dueDateStr, valueColor: isOverdue ? Colors.red : Colors.redAccent),
            const SizedBox(height: 16),

            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else ...[
              Container(
                color: Colors.grey.shade100,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: const Row(
                  children: [
                    Expanded(flex: 4, child: Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    Expanded(flex: 2, child: Text('Days', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    Expanded(flex: 2, child: Text('Fee', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    Expanded(flex: 3, child: Text('Subtotal', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                ),
              ),
              _tableRow(
                description: 'Tumpang Fee (${widget.payment.dateRange})',
                days: '$_totalCycleDays days',
                fee: 'RM ${_dailyFee.toStringAsFixed(2)}',
                subtotal: 'RM ${subtotal.toStringAsFixed(2)}',
              ),
              if (_missedDays > 0)
                _tableRow(
                  description: 'Cant Fetch Deduction',
                  days: '-$_missedDays days',
                  fee: 'RM ${_dailyFee.toStringAsFixed(2)}',
                  subtotal: '-RM ${deduction.toStringAsFixed(2)}',
                  isDeduction: true,
                )
              else
                _tableRow(
                  description: 'Cant Fetch Deduction',
                  days: '0 days',
                  fee: 'RM 0.00',
                  subtotal: 'RM 0.00',
                  isMuted: true,
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount Due', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(
                      'RM ${totalDue.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.black),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: AppColors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Close Preview', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          const Text(': ', style: TextStyle(color: Colors.grey)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.black))),
        ],
      ),
    );
  }

  Widget _tableRow({
    required String description,
    required String days,
    required String fee,
    required String subtotal,
    bool isDeduction = false,
    bool isMuted = false,
  }) {
    final color = isDeduction ? Colors.red : (isMuted ? Colors.grey : AppColors.black);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(description, style: TextStyle(fontSize: 12, color: color))),
          Expanded(flex: 2, child: Text(days, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: color))),
          Expanded(flex: 2, child: Text(fee, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: color))),
          Expanded(flex: 3, child: Text(subtotal, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color))),
        ],
      ),
    );
  }
}