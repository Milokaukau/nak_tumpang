// Holds the selectedPayments Set, handles the "Select All" logic, and triggers the local data service. It extends ChangeNotifier.

import 'package:flutter/material.dart';
import '../../../core/entities/payment.dart';

class PaymentViewModel extends ChangeNotifier {
  // Hardcoded dummy data for UI testing
  List<Payment> pendingPayments = [
    Payment(
      id: 'pay_01',
      direction: 'Home ➔ TAR UMT',
      amount: 150.00,
      dueDate: DateTime(2026, 8, 7),
      dateRange: '01 Aug - 31 Aug 2026',
    ),
    Payment(
      id: 'pay_02',
      direction: 'TAR UMT ➔ KLCC',
      amount: 45.00,
      dueDate: DateTime(2026, 8, 10),
      dateRange: '05 Aug - 15 Aug 2026',
    ),
  ];

  Set<String> selectedPaymentIds = {};

  double get totalSelectedAmount {
    return pendingPayments
        .where((p) => selectedPaymentIds.contains(p.id))
        .fold(0, (sum, item) => sum + item.amount);
  }

  void toggleSelection(String id) {
    if (selectedPaymentIds.contains(id)) {
      selectedPaymentIds.remove(id);
    } else {
      selectedPaymentIds.add(id);
    }
    notifyListeners();
  }
}