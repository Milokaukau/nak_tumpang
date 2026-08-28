// The isolated UI widget for a single pending invoice, containing the route data, amount, and the checkbox for batch selection.

import 'package:flutter/material.dart';
import '../../../../core/entities/payment.dart';

class TumpangPaymentCard extends StatelessWidget {
  final Payment payment;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const TumpangPaymentCard({
    Key? key,
    required this.payment,
    required this.isSelected,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: CheckboxListTile(
        activeColor: Colors.amber,
        checkColor: Colors.black,
        value: isSelected,
        onChanged: onChanged,
        title: Text(
            payment.direction,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text('${payment.dateRange}\nDue: ${payment.dueDate.toString().split(' ')[0]}'),
        ),
        secondary: Text(
            'RM ${payment.amount.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)
        ),
      ),
    );
  }
}