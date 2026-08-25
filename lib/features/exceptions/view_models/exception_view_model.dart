import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ExceptionViewModel extends ChangeNotifier {
  DateTime? startDate;
  DateTime? endDate;
  String? selectedReason;
  final TextEditingController customReasonController = TextEditingController();
  bool isSubmitting = false;
  String? errorMessage;

  static const List<String> passengerReasons = [
    'Medical leave',
    'Public holiday',
    'Emergency',
    'Personal reasons',
    'Others',
  ];

  static const List<String> driverReasons = [
    'Medical leave',
    'Public holiday',
    'Emergency',
    'Vehicle issue',
    'Personal reasons',
    'Others',
  ];

  void setStartDate(DateTime date) {
    startDate = date;
    if (endDate != null && endDate!.isBefore(date)) endDate = null;
    notifyListeners();
  }

  void setEndDate(DateTime date) {
    if (startDate != null && date.isBefore(startDate!)) return; // block invalid pick
    endDate = date;
    notifyListeners();
  }

  void setReason(String? reason) {
    selectedReason = reason;
    notifyListeners();
  }

  Map<String, String> _formatDateRange() {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return {
      'start': fmt(startDate!),
      'end': fmt(endDate!),
    };
  }

  Future<bool> submitException({
    required String tumpangSubscriptionId,
    required String initiatedBy,
  }) async {
    if (startDate == null || endDate == null || selectedReason == null) return false;
    if (selectedReason == 'Others' && customReasonController.text.trim().isEmpty) return false;

    isSubmitting = true;
    notifyListeners();

    final reasonText =
    selectedReason == 'Others' ? customReasonController.text.trim() : selectedReason!;

    try {
      await FirebaseFirestore.instance.collection('tumpang_exception').add({
        'tumpang_subscription_id': tumpangSubscriptionId,
        'initiated_by': initiatedBy,
        'dates': _formatDateRange(),
        'reason': reasonText,
      });
      isSubmitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Failed to submit: $e';
      isSubmitting = false;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    customReasonController.dispose();
    super.dispose();
  }
}