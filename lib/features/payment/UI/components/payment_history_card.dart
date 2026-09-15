import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/entities/payment.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payment/UI/components/invoice_sheet.dart';

class PaymentHistoryCard extends StatelessWidget {
  final Payment payment;

  const PaymentHistoryCard({super.key, required this.payment});

  String _formatDateDdMmYyyy(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final paidDateStr = payment.paidAt != null
        ? _formatDateDdMmYyyy(payment.paidAt!)
        : 'Completed';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.greyBorder, width: 1.0),
      ),
      elevation: 0,
      color: AppColors.white,
      // Wrap the content with InkWell to make the card clickable
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          InvoiceSheet.show(context, payment);
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      payment.direction,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.black),
                    ),
                  ),
                  Text(
                    'RM ${payment.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(payment.dateRange, style: const TextStyle(fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 4),
                      Text('Paid on $paidDateStr', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'View Receipt',
                        style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ref: ${payment.id.length > 12 ? payment.id.substring(0, 12) : payment.id}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}