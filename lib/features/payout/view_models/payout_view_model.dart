import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/utils/validators.dart';
import 'package:nak_tumpang/features/payout/data/services/payout_service.dart';

enum PayoutMethod { bankTransfer, tngEwallet }

extension PayoutMethodDb on PayoutMethod {
  /// The value stored in payout_history.payment_method.
  String get dbValue => this == PayoutMethod.bankTransfer ? 'bank_transfer' : 'tng_ewallet';

  static PayoutMethod fromDb(String? value) =>
      value == 'tng_ewallet' ? PayoutMethod.tngEwallet : PayoutMethod.bankTransfer;
}

enum PayoutView { wallet, history }

class PayoutHistoryDisplay {
  final String id;
  final double amount;
  final String status; // pending / processing / paid
  final PayoutMethod paymentMethod;
  final String? bankName;
  final String bankAccNo;
  final DateTime? requestedAt;

  PayoutHistoryDisplay({
    required this.id,
    required this.amount,
    required this.status,
    required this.paymentMethod,
    this.bankName,
    required this.bankAccNo,
    this.requestedAt,
  });

  bool get isEwallet => paymentMethod == PayoutMethod.tngEwallet;

  String get destinationLabel => isEwallet ? "Touch 'n Go eWallet" : (bankName ?? 'Bank transfer');
}

class RecentTripDisplay {
  final String tripId; // tumpang_request.id — shown as a reference on the receipt
  final String passengerName;
  final String pickupName;
  final String dropoffName;
  final double points;
  final String monthLabel; // e.g. "August"
  final DateTime? tripDate; // full date, for the trip detail popup

  RecentTripDisplay({
    required this.tripId,
    required this.passengerName,
    required this.pickupName,
    required this.dropoffName,
    required this.points,
    required this.monthLabel,
    this.tripDate,
  });
}

class PayoutViewModel extends ChangeNotifier {
  PayoutViewModel() {
    ewalletPhoneFocusNode.addListener(notifyListeners);
  }

  final _service = PayoutService();

  bool isLoading = true;
  String? errorMessage;

  double totalEarnings = 0;
  double availableBalance = 0;
  double totalWithdrawn = 0;

  int tripsCompletedCount = 0;
  double thisMonthPoints = 0;
  List<RecentTripDisplay> recentTrips = [];

// tab toggle between history and wallet
  PayoutView currentView = PayoutView.wallet;
  bool isHistoryLoading = false;
  String? historyError;
  List<PayoutHistoryDisplay> payoutHistory = [];

// payout form state
  PayoutMethod selectedMethod = PayoutMethod.bankTransfer;
  final amountController = TextEditingController();

// bank name is a fixed dropdown of malaysian banks
  String? selectedBankName;
  final bankAccNoController = TextEditingController();
  final ewalletPhoneController = TextEditingController();
  final ewalletPhoneFocusNode = FocusNode();

  bool isSubmitting = false;
  String? amountError;
  String? bankNameError;
  String? bankAccNoError;
  String? ewalletPhoneError;

  String? lastPayoutId;
  String payoutStatus = 'pending';

  @override
  void dispose() {
    amountController.dispose();
    bankAccNoController.dispose();
    ewalletPhoneController.dispose();
    ewalletPhoneFocusNode.dispose();
    super.dispose();
  }

  void setView(PayoutView view) {
    currentView = view;
    notifyListeners();
    if (view == PayoutView.history && payoutHistory.isEmpty && historyError == null) {
      loadHistory();
    }
  }

  Future<void> loadHistory() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    isHistoryLoading = true;
    historyError = null;
    notifyListeners();

    try {
      final rows = await _service.fetchPayoutHistory(userId);
      payoutHistory = rows.map((row) {
        final dateStr = row['requested_at'] as String?;
        return PayoutHistoryDisplay(
          id: row['id'] as String? ?? '-',
          amount: (row['amount'] as num?)?.toDouble() ?? 0,
          status: row['status'] as String? ?? 'pending',
          paymentMethod: PayoutMethodDb.fromDb(row['payment_method'] as String?),
          bankName: row['bank_name'] as String?,
          bankAccNo: row['bank_acc_no'] as String? ?? '-',
          requestedAt: dateStr != null ? DateTime.tryParse(dateStr) : null,
        );
      }).toList();
    } catch (e) {
      historyError = 'Could not load payout history. Please try again.';
    } finally {
      isHistoryLoading = false;
      notifyListeners();
    }
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
            tripId: trip['id']?.toString() ?? '-',
            passengerName: passengerName,
            pickupName: trip['pickup_name'] as String? ?? '-',
            dropoffName: trip['dropoff_name'] as String? ?? '-',
            points: fee,
            monthLabel: date != null ? _monthName(date.month) : '-',
            tripDate: date,
          ));
        }
      }

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

  void notifyUiOnly() => notifyListeners();

  void selectMethod(PayoutMethod method) {
    selectedMethod = method;
    notifyListeners();
  }

  void selectBank(String? bank) {
    selectedBankName = bank;
    bankNameError = null;
    notifyListeners();
  }

  void clearBankAccNoError() {
    bankAccNoError = null;
    notifyListeners();
  }

  void clearEwalletPhoneError() {
    ewalletPhoneError = null;
    notifyListeners();
  }

  bool validateAmount() {
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      amountError = 'Enter a valid amount';
    } else if (amount > availableBalance) {
      amountError = 'Amount exceeds your available balance';
    } else {
      amountError = null;
    }
    notifyListeners();
    return amountError == null;
  }

  bool validateDetails() {
    if (selectedMethod == PayoutMethod.bankTransfer) {
      bankNameError = Validators.bankName(selectedBankName);
      bankAccNoError = Validators.bankAccountNumber(bankAccNoController.text);
      ewalletPhoneError = null;
    } else {
      ewalletPhoneError = Validators.phoneLocal(ewalletPhoneController.text);
      bankNameError = null;
      bankAccNoError = null;
    }
    notifyListeners();
    return bankNameError == null && bankAccNoError == null && ewalletPhoneError == null;
  }

// clears screen when driver goes back to select payment method or change amount
  void resetDetailsFields() {
    selectedBankName = null;
    bankAccNoController.clear();
    ewalletPhoneController.clear();
    bankNameError = null;
    bankAccNoError = null;
    ewalletPhoneError = null;
  }

  Future<bool> submitPayout() async {
    if (!validateAmount() || !validateDetails()) {
      return false;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    final amount = double.parse(amountController.text.trim());
    final newBalance = availableBalance - amount;

    // e-wallet payouts have no bank, bank_name goes in as null
    final bankName = selectedMethod == PayoutMethod.bankTransfer ? selectedBankName : null;

    final bankAccNo = selectedMethod == PayoutMethod.bankTransfer
        ? bankAccNoController.text.trim()
        : Validators.toStoredPhone(ewalletPhoneController.text);

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      final payoutId = await _service.requestPayout(
        userId: userId,
        amount: amount,
        newBalance: newBalance,
        paymentMethod: selectedMethod.dbValue,
        bankName: bankName,
        bankAccNo: bankAccNo,
      );
      availableBalance = newBalance;
      lastPayoutId = payoutId;
      payoutStatus = 'pending';

      payoutHistory.insert(
        0,
        PayoutHistoryDisplay(
          id: payoutId,
          amount: amount,
          status: 'pending',
          paymentMethod: selectedMethod,
          bankName: bankName,
          bankAccNo: bankAccNo,
          requestedAt: DateTime.now(),
        ),
      );

      return true;
    } catch (e) {
      errorMessage = 'Could not process payout. Please try again.';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  // fake animation for transaction processing demo
  Future<void> runPayoutStatusAnimation() async {
    final payoutId = lastPayoutId;
    if (payoutId == null) return;

    payoutStatus = 'pending';
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 1200));
    payoutStatus = 'processing';
    _syncHistoryStatus(payoutId, 'processing');
    notifyListeners();
    _service.updatePayoutStatus(payoutId, 'processing');

    await Future.delayed(const Duration(milliseconds: 1600));
    payoutStatus = 'paid';
    _syncHistoryStatus(payoutId, 'paid');
    notifyListeners();
    _service.updatePayoutStatus(payoutId, 'paid');
  }

  void _syncHistoryStatus(String payoutId, String status) {
    final index = payoutHistory.indexWhere((p) => p.id == payoutId);
    if (index == -1) return;
    final old = payoutHistory[index];
    payoutHistory[index] = PayoutHistoryDisplay(
      id: old.id,
      amount: old.amount,
      status: status,
      paymentMethod: old.paymentMethod,
      bankName: old.bankName,
      bankAccNo: old.bankAccNo,
      requestedAt: old.requestedAt,
    );
  }
}