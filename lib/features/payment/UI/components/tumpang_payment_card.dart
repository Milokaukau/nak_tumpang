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
    final dueDateStr = '${payment.dueDate.day.toString().padLeft(2, '0')}-${payment.dueDate.month.toString().padLeft(2, '0')}-${payment.dueDate.year}';

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
      // Wrap in InkWell so the entire card is clickable like a List Tile
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!isSelected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Left Side: Amount (Replaces the "secondary" widget)
              Text(
                'RM ${payment.amount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.black),
              ),
              const SizedBox(width: 16),

              // 2. Middle: Title & Subtitle (Wrapped in Expanded to prevent horizontal overflow)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // Allows the column to grow vertically as needed
                  children: [
                    Text(
                      payment.direction,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.black),
                    ),
                    const SizedBox(height: 6),
                    Text(payment.dateRange, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text('Due Date: $dueDateStr', style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      // Stop the tap from bubbling up and checking/unchecking the box
                      onTap: () => ProformaInvoiceSheet.show(context, payment),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long, size: 14, color: Colors.blue),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'View Invoice Details',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 3. Right Side: Checkbox
              Checkbox(
                activeColor: AppColors.primaryYellow,
                checkColor: AppColors.black,
                value: isSelected,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // Tightens up extra padding
              ),
            ],
          ),
        ),
      ),
    );
  }
}
