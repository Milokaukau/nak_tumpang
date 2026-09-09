import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/entities/payment.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payment/UI/components/proforma_invoice_sheet.dart';

class TumpangPaymentCard extends StatelessWidget {
  final Payment payment;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const TumpangPaymentCard({
    super.key,
    required this.payment,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dueDateStr = payment.dueDate.toIso8601String().split('T').first;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? AppColors.primaryYellow : AppColors.greyBorder,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      elevation: 0,
      color: AppColors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            CheckboxListTile(
              activeColor: AppColors.primaryYellow,
              checkColor: AppColors.black,
              value: isSelected,
              onChanged: onChanged,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Text(
                payment.direction,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.black),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(payment.dateRange, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text('Due Date: $dueDateStr', style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => ProformaInvoiceSheet.show(context, payment),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long, size: 14, color: Colors.blue),
                          SizedBox(width: 4),
                          Text(
                            'View Invoice Details',
                            style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              secondary: Text(
                'RM ${payment.amount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}