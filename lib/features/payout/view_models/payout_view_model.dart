import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/features/payout/data/services/payout_service.dart';

enum PayoutMethod { bankTransfer, tngEwallet }

/// A single row for the "Recent trips" list. Points = fee, per the 1
/// pt = RM1 conversion used everywhere else in the wallet.
class RecentTripDisplay {
  final String passengerName;
  final String pickupName;
  final String dropoffName;
  final double points;
  final String monthLabel; // e.g. "August"

  RecentTripDisplay({
    required this.passengerName,
    required this.pickupName,
    required this.dropoffName,
    required this.points,
    required this.monthLabel,
  });
}

/// Holds all state and logic for the driver wallet / payout flow
/// (balance screen, method screen, confirm). Supabase calls and
/// validation live here — screens only read state and call into it.
class PayoutViewModel extends ChangeNotifier {
  final _service = PayoutService();

  bool isLoading = true;
  String? errorMessage;

  double totalEarnings = 0;
  double availableBalance = 0;
  double totalWithdrawn = 0;

  int tripsCompletedCount = 0;
  double thisMonthPoints = 0;
  List<RecentTripDisplay> recentTrips = [];

  // --- Payout form state ---
  PayoutMethod selectedMethod = PayoutMethod.bankTransfer;
  final amountController = TextEditingController();
  final bankNameController = TextEditingController();
  final bankAccNoController = TextEditingController();
  final ewalletPhoneController = TextEditingController();

  bool isSubmitting = false;
  String? amountError;
  String? bankNameError;
  String? bankAccNoError;
  String? ewalletPhoneError;

  @override
  void dispose() {
    amountController.dispose();
    bankNameController.dispose();
    bankAccNoController.dispose();
    ewalletPhoneController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      isLoading = false;
      errorMessage = 'Not signed in.';
      notifyListeners();
      return;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final profile = await _service.fetchDriverProfile(userId);
      totalEarnings = (profile?['total_earnings'] as num?)?.toDouble() ?? 0;
      availableBalance = (profile?['available_balance'] as num?)?.toDouble() ?? 0;
      totalWithdrawn = (profile?['total_withdrawn'] as num?)?.toDouble() ?? 0;

      final trips = await _service.fetchCompletedTrips(userId);
      tripsCompletedCount = trips.length;

      final now = DateTime.now();
      thisMonthPoints = 0;
      recentTrips = [];

      for (final trip in trips) {
        final fee = (trip['fee'] as num?)?.toDouble() ?? 0;
        final dateStr = trip['sub_start_date'] as String?;
        final date = dateStr != null ? DateTime.tryParse(dateStr) : null;

        if (date != null && date.year == now.year && date.month == now.month) {
          thisMonthPoints += fee;
        }

        if (recentTrips.length < 10) {
          final passengerName =
              trip['passenger_trips']?['users']?['name'] as String? ?? 'Passenger';
          recentTrips.add(RecentTripDisplay(
            passengerName: passengerName,
            pickupName: trip['pickup_name'] as String? ?? '-',
            dropoffName: trip['dropoff_name'] as String? ?? '-',
            points: fee,
            monthLabel: date != null ? _monthName(date.month) : '-',
          ));
        }
      }

      // Amount field starts at the full balance, matching the mockup's
      // default — the driver can still edit it down.
      amountController.text = availableBalance.toStringAsFixed(2);
    } catch (e) {
      errorMessage = 'Could not load wallet. Please try again.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  String _monthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names[month - 1];
  }

  /// Call after the amount field changes so the screen rebuilds (e.g.
  /// to clear a stale error as the driver retypes).
  void notifyUiOnly() => notifyListeners();

  void selectMethod(PayoutMethod method) {
    selectedMethod = method;
    notifyListeners();
  }

  void _runValidation() {
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      amountError = 'Enter a valid amount';
    } else if (amount > availableBalance) {
      amountError = 'Amount exceeds your available balance';
    } else {
      amountError = null;
    }

    if (selectedMethod == PayoutMethod.bankTransfer) {
      bankNameError = bankNameController.text.trim().isEmpty ? 'Bank name is required' : null;
      bankAccNoError =
      bankAccNoController.text.trim().isEmpty ? 'Account number is required' : null;
      ewalletPhoneError = null;
    } else {
      ewalletPhoneError =
      ewalletPhoneController.text.trim().isEmpty ? 'Phone number is required' : null;
      bankNameError = null;
      bankAccNoError = null;
    }
  }

  /// Returns true on success. On failure, check amountError/bankNameError/
  /// bankAccNoError/ewalletPhoneError/errorMessage for what to show.
  Future<bool> submitPayout() async {
    _runValidation();
    notifyListeners();

    if (amountError != null || bankNameError != null || bankAccNoError != null || ewalletPhoneError != null) {
      return false;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    final amount = double.parse(amountController.text.trim());
    final newBalance = availableBalance - amount;

    // payout_history has bank_name/bank_acc_no as its only fields for
    // where the money goes — there's no separate e-wallet column, so a
    // Touch 'n Go payout is logged with a fixed bank_name label and the
    // phone number in bank_acc_no. Flag this to your team if you'd
    // rather add a proper `method`/`ewallet_phone` column instead.
    final bankName = selectedMethod == PayoutMethod.bankTransfer
        ? bankNameController.text.trim()
        : "Touch 'n Go eWallet";
    final bankAccNo = selectedMethod == PayoutMethod.bankTransfer
        ? bankAccNoController.text.trim()
        : ewalletPhoneController.text.trim();

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _service.requestPayout(
        userId: userId,
        amount: amount,
        newBalance: newBalance,
        bankName: bankName,
        bankAccNo: bankAccNo,
      );
      availableBalance = newBalance;
      return true;
    } catch (e) {
      errorMessage = 'Could not process payout. Please try again.';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }
}
