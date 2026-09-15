import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/entities/payment.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payment/view_models/payment_view_model.dart';

class InvoiceSheet extends StatefulWidget {
  final Payment payment;

  const InvoiceSheet({super.key, required this.payment});

  static Future<void> show(BuildContext context, Payment payment) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InvoiceSheet(payment: payment),
    );
  }

  @override
  State<InvoiceSheet> createState() => _InvoiceSheetState();
}

class _InvoiceSheetState extends State<InvoiceSheet> {
  bool _loading = true;

  double _dailyFee = 0.0;
  int _activeCycleDays = 0;
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

  bool _isDayActive(DateTime date, Map<String, dynamic> schedule) {
    switch (date.weekday) {
      case DateTime.monday:
        return schedule['active_monday'] == true;
      case DateTime.tuesday:
        return schedule['active_tuesday'] == true;
      case DateTime.wednesday:
        return schedule['active_wednesday'] == true;
      case DateTime.thursday:
        return schedule['active_thursday'] == true;
      case DateTime.friday:
        return schedule['active_friday'] == true;
      case DateTime.saturday:
        return schedule['active_saturday'] == true;
      case DateTime.sunday:
        return schedule['active_sunday'] == true;
      default:
        return false;
    }
  }

  Future<void> _loadInvoiceDetails() async {
    try {
      final start = widget.payment.cycleStartDate;
      final end = widget.payment.cycleEndDate;
      final details = await context.read<PaymentViewModel>().loadProformaInvoiceDetails(
        subscriptionId: widget.payment.subscriptionId,
        cycleStart: start,
        cycleEnd: end,
      );
      if (details == null) {
        _loadError = context.read<PaymentViewModel>().proformaErrorMessage;
        return;
      }

      _dailyFee = details['dailyFee'] as double;
      _passengerTripName = details['passengerTripName'] as String?;
      _driverTripName = details['driverTripName'] as String?;
      final schedule = details['schedule'] as Map<String, dynamic>;
      if (start != null && end != null) {
        for (var date = start; !date.isAfter(end); date = date.add(const Duration(days: 1))) {
          if (_isDayActive(date, schedule)) _activeCycleDays++;
        }

        final dates = <String>{};
        for (final row in (details['exceptions'] as List)) {
          final s = DateTime.parse(row['start_date'].toString());
          final e = DateTime.parse(row['end_date'].toString());
          final overlapStart = s.isBefore(start) ? start : s;
          final overlapEnd = e.isAfter(end) ? end : e;
          for (DateTime d = overlapStart; !d.isAfter(overlapEnd); d = d.add(const Duration(days: 1))) {
            if (_isDayActive(d, schedule)) {
              dates.add(d.toIso8601String().split('T').first);
            }
          }
        }
        _missedDateList = dates.toList()..sort();
        if (_dailyFee > 0) {
          final subtotal = _activeCycleDays * _dailyFee;
          _missedDays = ((subtotal - widget.payment.amount) / _dailyFee)
              .round()
              .clamp(0, _activeCycleDays);
        } else {
          _missedDays = dates.length;
        }
      } else {
        if (_dailyFee > 0) {
          _activeCycleDays = (widget.payment.amount / _dailyFee).round();
        }
      }
    } catch (e) {
      debugPrint('Error loading invoice details: $e');
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
    final dueDateStr = _formatDateDdMmYyyy(widget.payment.dueDate);
    final subtotal = _activeCycleDays * _dailyFee;
    final deduction = _missedDays * _dailyFee;

    final isPaid = widget.payment.paidAt != null;
    final isOverdue = !isPaid && DateTime.now().isAfter(widget.payment.dueDate);

    final totalDue = isPaid
        ? widget.payment.amount
        : (_loadError != null
        ? widget.payment.amount
        : (subtotal - deduction).clamp(0, double.infinity));

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
                    Text(
                      isPaid ? 'RECEIPT DETAILS' : 'INVOICE DETAILS',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
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
                    color: isPaid ? Colors.green.shade50 : (isOverdue ? Colors.red.shade50 : Colors.orange.shade50),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isPaid ? Colors.green.shade200 : (isOverdue ? Colors.red.shade200 : Colors.orange.shade200)),
                  ),
                  child: Text(
                    isPaid ? 'PAID' : (isOverdue ? 'OVERDUE' : 'UNPAID'),
                    style: TextStyle(
                        color: isPaid ? Colors.green : (isOverdue ? Colors.red : Colors.orange),
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
                  '$_loadError The ${isPaid ? 'Total Amount Paid' : 'Total Amount Due'} below is still accurate.',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            if (tripNameText.isNotEmpty) _infoRow('Trip Name', tripNameText),
            _infoRow('Service Route', widget.payment.direction),
            _infoRow('Billing Period', billingPeriodText),
            if (isPaid)
              _infoRow('Paid On', _formatDateDdMmYyyy(widget.payment.paidAt!), valueColor: Colors.green)
            else
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
                    Expanded(flex: 3, child: Text('Scheduled\nDays', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    Expanded(flex: 2, child: Text('Fee', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    Expanded(flex: 3, child: Text('Subtotal', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                ),
              ),
              _tableRow(
                description: 'Tumpang Fee (${widget.payment.dateRange})',
                days: '$_activeCycleDays days',
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
                    Text(
                        isPaid ? 'Total Amount Paid' : 'Total Amount Due',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                    ),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
            ),
          ),
          const Text(
            ':   ',
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.black,
                height: 1.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
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
          Expanded(flex: 3, child: Text(days, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: color))),
          Expanded(flex: 2, child: Text(fee, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: color))),
          Expanded(flex: 3, child: Text(subtotal, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color))),
        ],
      ),
    );
  }
}