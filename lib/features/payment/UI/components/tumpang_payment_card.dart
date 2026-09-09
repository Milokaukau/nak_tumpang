import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/entities/payment.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

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
      child: CheckboxListTile(
        activeColor: AppColors.primaryYellow,
        checkColor: AppColors.black,
        value: isSelected,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              Text('Due Date: $dueDateStr', style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        secondary: Text(
          'RM ${payment.amount.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.black),
        ),
      ),
    );
  }
}