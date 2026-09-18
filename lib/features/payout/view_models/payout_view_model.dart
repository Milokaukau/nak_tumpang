import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/utils/validators.dart';
import 'package:nak_tumpang/features/payout/data/services/payout_gateway.dart';
import 'package:nak_tumpang/features/payout/data/services/payout_local_service.dart';
import 'package:nak_tumpang/features/payout/data/services/payout_service.dart';

enum PayoutMethod { bankTransfer, tngEwallet }

const double kFallbackBankTransferFee = 1.00;

const double kMinPayoutAmount = 10.00;

final RegExp _amountFormatRegex = RegExp(r'^\d+$');

double payoutNetAmount(double grossAmount, PayoutMethod method, double bankTransferFee) =>
    method == PayoutMethod.bankTransfer
        ? (grossAmount - bankTransferFee < 0 ? 0 : grossAmount - bankTransferFee)
        : grossAmount;


String payoutStatusLabel(String status) => switch (status) {
  'completed' => 'Paid',
  'processing' => 'Processing',
  'failed' => 'Failed',
  _ => 'Pending',
};

Color payoutStatusColor(String status) => switch (status) {
  'completed' => Colors.green,
  'processing' => Colors.orange,
  'failed' => Colors.red,
  _ => AppColors.greyText,
};

String pointsLabel(double amount) => amount.floor().toString();

extension PayoutMethodDb on PayoutMethod {
  String get dbValue => this == PayoutMethod.bankTransfer ? 'bank_transfer' : 'tng_ewallet';

  static PayoutMethod fromDb(String? value) =>
      value == 'tng_ewallet' ? PayoutMethod.tngEwallet : PayoutMethod.bankTransfer;
}

enum PayoutView { wallet, history }

class PayoutHistoryDisplay {
  final String id;
  final double amount;
  final String status;
  final PayoutMethod paymentMethod;
  final String? bankName;
  final String? bankAccNo;
  final String? ewalletPhone;
  final DateTime? requestedAt;
  final double? fee;

  PayoutHistoryDisplay({
    required this.id,
    required this.amount,
    required this.status,
    required this.paymentMethod,
    this.bankName,
    this.bankAccNo,
    this.ewalletPhone,
    this.requestedAt,
    this.fee,
  });

  bool get isEwallet => paymentMethod == PayoutMethod.tngEwallet;

  String get destinationLabel => isEwallet ? "Touch 'n Go eWallet" : (bankName ?? 'Bank transfer');

  double get resolvedFee => fee ?? (paymentMethod == PayoutMethod.bankTransfer ? kFallbackBankTransferFee : 0);

  double get netAmount {
    final net = amount - resolvedFee;
    return net < 0 ? 0 : net;
  }

  String get _destination => (isEwallet ? ewalletPhone : bankAccNo) ?? '-';

  String get maskedDestination {
    final value = _destination;
    if (value.length <= 4) return '•' * value.length;
    return '•••• ${value.substring(value.length - 4)}';
  }

  factory PayoutHistoryDisplay.fromRow(Map<String, dynamic> row) {
    final dateStr = row['requested_at'] as String?;
    return PayoutHistoryDisplay(
      id: row['id'] as String? ?? '-',
      amount: (row['amount'] as num?)?.toDouble() ?? 0,
      status: row['status'] as String? ?? 'pending',
      paymentMethod: PayoutMethodDb.fromDb(row['payment_method'] as String?),
      bankName: row['bank_name'] as String?,
      bankAccNo: row['bank_acc_no'] as String?,
      ewalletPhone: row['ewallet_phone'] as String?,
      requestedAt: dateStr != null ? DateTime.tryParse(dateStr) : null,
      fee: (row['fee'] as num?)?.toDouble(),
    );
  }
}

class RecentTripDisplay {
  final String tripId;
  final String passengerName;
  final String tripName;
  final String pickupName;
  final String dropoffName;
  final double points;
  final double grossAmount;
  final double platformFee;
  final double dailyFee;
  final DateTime? cycleStartDate;
  final DateTime? cycleEndDate;
  final String monthLabel;
  final DateTime? tripDate;

  RecentTripDisplay({
    required this.tripId,
    required this.passengerName,
    required this.tripName,
    required this.pickupName,
    required this.dropoffName,
    required this.points,
    required this.grossAmount,
    required this.platformFee,
    required this.dailyFee,
    this.cycleStartDate,
    this.cycleEndDate,
    required this.monthLabel,
    this.tripDate,
  });

  int get billableDays => dailyFee > 0 ? (grossAmount / dailyFee).round() : 0;
}

class PayoutViewModel extends ChangeNotifier {
  PayoutViewModel({PayoutGateway? gateway}) : _gateway = gateway ?? MockPayoutGateway() {
    ewalletPhoneFocusNode.addListener(notifyListeners);
  }

  final _service = PayoutService();
  final _localService = PayoutLocalService();
  final PayoutGateway _gateway;

  bool isLoading = true;
  String? errorMessage;
  String? walletNotice;

  double totalEarnings = 0;
  double availableBalance = 0;
  double totalWithdrawn = 0;

  double bankTransferFee = kFallbackBankTransferFee;

  int tripsCompletedCount = 0;
  double thisMonthPoints = 0;
  List<RecentTripDisplay> recentTrips = [];

  PayoutView currentView = PayoutView.wallet;
  bool isHistoryLoading = false;
  bool isLoadingMoreHistory = false;
  bool hasMoreHistory = true;
  String? historyError;
  String? historyNotice;
  List<PayoutHistoryDisplay> payoutHistory = [];

  static const int _historyPageSize = 20;
  int _historyOffset = 0;

  List<DateTime> _historyDates = [];
  bool _historyDatesLoaded = false;

  int? selectedHistoryYear;
  DateTime? selectedHistoryMonth;
  bool get hasAnyHistory => _historyDates.isNotEmpty;

  List<int> get historyYears {
    final years = _historyDates.map((d) => d.year).toSet().toList();
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  List<DateTime> get historyMonths {
    final year = selectedHistoryYear;
    final months = <DateTime>{};
    for (final date in _historyDates) {
      if (year != null && date.year != year) continue;
      months.add(DateTime(date.year, date.month));
    }
    final list = months.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  List<PayoutHistoryDisplay> get filteredPayoutHistory => payoutHistory;

  void selectHistoryYear(int? year) {
    selectedHistoryYear = year;
    selectedHistoryMonth = null;
    _reloadHistoryForCurrentScope();
  }

  void selectHistoryMonth(DateTime? month) {
    selectedHistoryMonth = month;
    _reloadHistoryForCurrentScope();
  }

  PayoutMethod selectedMethod = PayoutMethod.bankTransfer;
  final amountController = TextEditingController(text: '0');

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

  Map<String, String> pendingReconciliation = {};

  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  bool _isConnectivityError(Object error) =>
      error is SocketException || error is TimeoutException || error is http.ClientException;

  String _fetchFailureMessage(Object error, {required String whenOffline, required String whenOnline}) {
    return _isConnectivityError(error) ? whenOffline : whenOnline;
  }

  @override
  void dispose() {
    _disposed = true;
    amountController.dispose();
    bankAccNoController.dispose();
    ewalletPhoneController.dispose();
    ewalletPhoneFocusNode.removeListener(notifyListeners);
    ewalletPhoneFocusNode.dispose();
    super.dispose();
  }

  void setView(PayoutView view) {
    currentView = view;
    notifyListeners();
    if (view == PayoutView.history && !_historyDatesLoaded && historyError == null) {
      loadHistory();
    }
  }

  Future<void> loadHistory() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    isHistoryLoading = true;
    historyError = null;
    historyNotice = null;
    notifyListeners();

    try {
      await _applyPendingReconciliations();
      if (!_historyDatesLoaded) {
        _historyDates = await _service.fetchPayoutHistoryDates(userId);
        _historyDatesLoaded = true;
      }
      await _fetchHistoryPage(userId, reset: true);
    } catch (e) {
      debugPrint('loadHistory failed, falling back to local cache: $e');
      _historyDates = await _localService.getCachedPayoutHistoryDates(userId);
      _historyDatesLoaded = true;
      final cachedRows = await _localService.getCachedPayoutHistoryPage(
        userId,
        limit: _historyPageSize,
        offset: 0,
        year: selectedHistoryYear,
        month: selectedHistoryMonth?.month,
      );
      if (cachedRows.isNotEmpty) {
        payoutHistory = _applyReconciliationOverlay(cachedRows.map(PayoutHistoryDisplay.fromRow).toList());
        _historyOffset = payoutHistory.length;
        historyNotice = _fetchFailureMessage(
          e,
          whenOffline: "Showing your last saved history — you're offline.",
          whenOnline: 'Could not load the latest history — showing your last saved version.',
        );
      } else {
        historyError = _fetchFailureMessage(
          e,
          whenOffline: "You're offline and there's no saved history yet.",
          whenOnline: 'Could not load payout history. Please try again.',
        );
      }
    } finally {
      isHistoryLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshHistory() => _reloadHistoryForCurrentScope();

  Future<void> _reloadHistoryForCurrentScope() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    isHistoryLoading = true;
    historyError = null;
    historyNotice = null;
    payoutHistory = [];
    notifyListeners();

    try {
      await _applyPendingReconciliations();
      await _fetchHistoryPage(userId, reset: true);
    } catch (e) {
      debugPrint('_reloadHistoryForCurrentScope failed, falling back to local cache: $e');
      final cachedRows = await _localService.getCachedPayoutHistoryPage(
        userId,
        limit: _historyPageSize,
        offset: 0,
        year: selectedHistoryYear,
        month: selectedHistoryMonth?.month,
      );
      if (cachedRows.isNotEmpty) {
        payoutHistory = _applyReconciliationOverlay(cachedRows.map(PayoutHistoryDisplay.fromRow).toList());
        _historyOffset = payoutHistory.length;
        hasMoreHistory = false;
        historyNotice = _fetchFailureMessage(
          e,
          whenOffline: "Showing your last saved history — you're offline.",
          whenOnline: 'Could not load the latest history — showing your last saved version.',
        );
      } else {
        historyError = _fetchFailureMessage(
          e,
          whenOffline: "You're offline and there's no saved history yet.",
          whenOnline: 'Could not load payout history. Please try again.',
        );
      }
    } finally {
      isHistoryLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreHistory() async {
    if (isLoadingMoreHistory || isHistoryLoading || !hasMoreHistory) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    isLoadingMoreHistory = true;
    notifyListeners();
    try {
      await _fetchHistoryPage(userId, reset: false);
    } catch (e) {
      hasMoreHistory = true;
    } finally {
      isLoadingMoreHistory = false;
      notifyListeners();
    }
  }

  Future<void> _fetchHistoryPage(String userId, {required bool reset}) async {
    if (reset) {
      _historyOffset = 0;
      hasMoreHistory = true;
    }
    final rows = await _service.fetchPayoutHistoryPage(
      userId,
      limit: _historyPageSize,
      offset: _historyOffset,
      year: selectedHistoryYear,
      month: selectedHistoryMonth?.month,
    );
    await _localService.cachePayoutHistoryPage(rows);
    final page = rows.map(PayoutHistoryDisplay.fromRow).toList();
    final reconciled = _applyReconciliationOverlay(page);
    payoutHistory = reset ? reconciled : [...payoutHistory, ...reconciled];
    _historyOffset += page.length;
    hasMoreHistory = page.length == _historyPageSize;
  }

  List<PayoutHistoryDisplay> _applyReconciliationOverlay(List<PayoutHistoryDisplay> rows) => [
    for (final row in rows)
      if (pendingReconciliation.containsKey(row.id))
        PayoutHistoryDisplay(
          id: row.id,
          amount: row.amount,
          status: pendingReconciliation[row.id]!,
          paymentMethod: row.paymentMethod,
          bankName: row.bankName,
          bankAccNo: row.bankAccNo,
          ewalletPhone: row.ewalletPhone,
          requestedAt: row.requestedAt,
          fee: row.fee,
        )
      else
        row,
  ];

  Future<void> _applyPendingReconciliations() async {
    final persisted = await _localService.getPendingReconciliations();
    pendingReconciliation = {...persisted, ...pendingReconciliation};
    if (pendingReconciliation.isEmpty) return;

    for (final entry in Map<String, String>.from(pendingReconciliation).entries) {
      final payoutId = entry.key;
      final status = entry.value;
      try {
        await _service.updatePayoutStatus(payoutId, status);
        await _localService.updateCachedPayoutStatus(payoutId, status, processedAt: DateTime.now());
        await _localService.removePendingReconciliation(payoutId);
        pendingReconciliation.remove(payoutId);
      } catch (e) {
        debugPrint('_applyPendingReconciliations: still failing to persist $payoutId: $e');
      }
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
    walletNotice = null;
    notifyListeners();

    try {
      await _loadWalletData(userId);
    } catch (e) {
      debugPrint('load() failed, falling back to local cache: $e');
      final cached = await _localService.getCachedWalletBalance(userId);
      if (cached != null) {
        totalEarnings = (cached['total_earnings'] as num?)?.toDouble() ?? 0;
        availableBalance = (cached['available_balance'] as num?)?.toDouble() ?? 0;
        totalWithdrawn = (cached['total_withdrawn'] as num?)?.toDouble() ?? 0;
        final cachedFee = await _localService.getCachedBankTransferFee();
        if (cachedFee != null) bankTransferFee = cachedFee;
        try {
          await _loadWalletDataFromCache(userId);
        } catch (cacheError) {
          debugPrint('load(): failed to restore wallet trips from cache: $cacheError');
        }
        walletNotice = _fetchFailureMessage(
          e,
          whenOffline: "Showing your last saved wallet — you're offline.",
          whenOnline: 'Could not load the latest wallet — showing your last saved version.',
        );
      } else {
        errorMessage = _fetchFailureMessage(
          e,
          whenOffline: "You're offline and there's no saved wallet yet.",
          whenOnline: 'Could not load wallet. Please try again.',
        );
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }


  Future<void> refreshWallet() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _loadWalletData(userId);
      walletNotice = null;
    } catch (e) {
      walletNotice = _fetchFailureMessage(
        e,
        whenOffline: "You're offline — showing your last saved wallet.",
        whenOnline: 'Could not refresh wallet. Please try again.',
      );
    } finally {
      notifyListeners();
    }
  }

  Future<void> _loadWalletData(String userId) async {
    final profile = await _service.fetchDriverProfile(userId);
    totalEarnings = (profile?['total_earnings'] as num?)?.toDouble() ?? 0;
    availableBalance = (profile?['available_balance'] as num?)?.toDouble() ?? 0;
    totalWithdrawn = (profile?['total_withdrawn'] as num?)?.toDouble() ?? 0;
    await _localService.cacheWalletBalance(
      userId: userId,
      totalEarnings: totalEarnings,
      availableBalance: availableBalance,
      totalWithdrawn: totalWithdrawn,
    );

    try {
      bankTransferFee = await _service.fetchBankTransferFee();
      await _localService.cacheBankTransferFee(bankTransferFee);
    } catch (_) {
    }

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(
      now.month == 12 ? now.year + 1 : now.year,
      now.month == 12 ? 1 : now.month + 1,
      1,
    );

    final monthTrips = await _service.fetchCompletedTripsInRange(
      userId,
      start: monthStart,
      end: monthEnd,
    );
    thisMonthPoints = 0;
    tripsCompletedCount = 0;
    for (final trip in monthTrips) {
      thisMonthPoints += (trip['driver_net_amount'] as num?)?.toDouble() ?? 0;
      tripsCompletedCount++;
    }

    final recent = await _service.fetchRecentCompletedTrips(userId, limit: 10);
    recentTrips = recent.map((trip) {
      final dateStr = trip['paid_at'] as String?;
      final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
      final subscription = trip['tumpang_subscription'] as Map<String, dynamic>?;
      final passengerName =
          subscription?['passenger_trips']?['users']?['name'] as String? ?? 'Passenger';
      final driverTrip = subscription?['driver_trips'] as Map<String, dynamic>?;
      final cycleStartStr = trip['cycle_start_date'] as String?;
      final cycleEndStr = trip['cycle_end_date'] as String?;
      return RecentTripDisplay(
        tripId: trip['id']?.toString() ?? '-',
        passengerName: passengerName,
        tripName: driverTrip?['trip_name'] as String? ?? '-',
        pickupName: subscription?['pickup_location'] as String? ?? '-',
        dropoffName: subscription?['dropoff_location'] as String? ?? '-',
        points: (trip['driver_net_amount'] as num?)?.toDouble() ?? 0,
        grossAmount: (trip['amount'] as num?)?.toDouble() ?? 0,
        platformFee: (trip['platform_fee'] as num?)?.toDouble() ?? 0,
        dailyFee: double.tryParse(subscription?['fee']?.toString() ?? '') ?? 0,
        cycleStartDate: cycleStartStr != null ? DateTime.tryParse(cycleStartStr) : null,
        cycleEndDate: cycleEndStr != null ? DateTime.tryParse(cycleEndStr) : null,
        monthLabel: date != null ? _monthName(date.month) : '-',
        tripDate: date,
      );
    }).toList();

    try {
      await _localService.cacheDriverWalletTrips(
        userId: userId,
        monthRows: monthTrips,
        recentRows: recent,
      );
    } catch (e) {
      debugPrint('_loadWalletData: failed to cache wallet trips: $e');
    }
  }

  Future<void> _loadWalletDataFromCache(String userId) async {
    final monthRows = await _localService.getCachedMonthWalletTrips(userId);
    thisMonthPoints = 0;
    tripsCompletedCount = 0;
    for (final row in monthRows) {
      thisMonthPoints += (row['points'] as num?)?.toDouble() ?? 0;
      tripsCompletedCount++;
    }

    final recentRows = await _localService.getCachedRecentWalletTrips(userId);
    recentTrips = recentRows.map((row) {
      final dateStr = row['paid_at'] as String?;
      final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
      final cycleStartStr = row['cycle_start_date'] as String?;
      final cycleEndStr = row['cycle_end_date'] as String?;
      return RecentTripDisplay(
        tripId: row['id']?.toString() ?? '-',
        passengerName: row['passenger_name'] as String? ?? 'Passenger',
        tripName: row['trip_name'] as String? ?? '-',
        pickupName: row['pickup_name'] as String? ?? '-',
        dropoffName: row['dropoff_name'] as String? ?? '-',
        points: (row['points'] as num?)?.toDouble() ?? 0,
        grossAmount: (row['gross_amount'] as num?)?.toDouble() ?? 0,
        platformFee: (row['platform_fee'] as num?)?.toDouble() ?? 0,
        dailyFee: (row['daily_fee'] as num?)?.toDouble() ?? 0,
        cycleStartDate: cycleStartStr != null ? DateTime.tryParse(cycleStartStr) : null,
        cycleEndDate: cycleEndStr != null ? DateTime.tryParse(cycleEndStr) : null,
        monthLabel: date != null ? _monthName(date.month) : '-',
        tripDate: date,
      );
    }).toList();
  }

  String _monthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names[month - 1];
  }

  void notifyUiOnly() => notifyListeners();

  void setAmountToMax() {
    amountController.text = availableBalance.floor().toString();
    amountError = null;
    notifyListeners();
  }

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

  int _toCents(double rm) => (rm * 100).round();

  bool validateAmount() {
    final text = amountController.text.trim();
    final amount = double.tryParse(text);
    if (amount == null || amount <= 0 || !_amountFormatRegex.hasMatch(text)) {
      amountError = 'Enter a whole number amount (no cents)';
    } else if (amount < kMinPayoutAmount) {
      amountError = 'Minimum payout is RM${kMinPayoutAmount.toStringAsFixed(0)}';
    } else if (_toCents(amount) > _toCents(availableBalance)) {
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

  void resetDetailsFields() {
    amountController.text = '0';
    amountError = null;
    selectedBankName = null;
    bankAccNoController.clear();
    ewalletPhoneController.clear();
    bankNameError = null;
    bankAccNoError = null;
    ewalletPhoneError = null;
  }

  Future<bool> submitPayout() async {
    if (isSubmitting) return false;
    final amountValid = validateAmount();
    final detailsValid = validateDetails();
    if (!amountValid || !detailsValid) {
      return false;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    final amount = double.parse(amountController.text.trim());

    final bankName = selectedMethod == PayoutMethod.bankTransfer ? selectedBankName : null;

    final bankAccNo = selectedMethod == PayoutMethod.bankTransfer
        ? bankAccNoController.text.trim()
        : null;
    final ewalletPhone = selectedMethod == PayoutMethod.tngEwallet
        ? Validators.toStoredPhone(ewalletPhoneController.text)
        : null;

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _service.requestPayout(
        amount: amount,
        paymentMethod: selectedMethod.dbValue,
        bankName: bankName,
        bankAccNo: bankAccNo,
        ewalletPhone: ewalletPhone,
      );

      final rawPayoutId = result['payout_id'];
      final rawNewBalance = result['new_balance'];
      if (rawPayoutId is! String || rawNewBalance is! num) {
        debugPrint('PayoutViewModel.submitPayout: unexpected request_payout result shape: $result');
        await refreshWallet();
        await refreshHistory();
        walletNotice = "Your payout may have gone through, but we couldn't confirm it here — "
            'pull to refresh before trying again.';
        notifyListeners();
        return false;
      }

      final payoutId = rawPayoutId;
      availableBalance = rawNewBalance.toDouble();
      final fee = (result['fee'] as num?)?.toDouble();
      final cachedFee = fee ?? (selectedMethod == PayoutMethod.bankTransfer ? kFallbackBankTransferFee : 0);
      lastPayoutId = payoutId;
      payoutStatus = 'pending';
      final now = DateTime.now();

      await _localService.cacheWalletBalance(
        userId: userId,
        totalEarnings: totalEarnings,
        availableBalance: availableBalance,
        totalWithdrawn: totalWithdrawn,
      );
      await _localService.cachePayoutHistoryRow({
        'id': payoutId,
        'user_id': userId,
        'amount': amount,
        'bank_name': bankName,
        'bank_acc_no': bankAccNo,
        'ewallet_phone': ewalletPhone,
        'status': 'pending',
        'requested_at': now.toIso8601String(),
        'processed_at': null,
        'payment_method': selectedMethod.dbValue,
        'fee': cachedFee,
      });

      final matchesYear = selectedHistoryYear == null || selectedHistoryYear == now.year;
      final matchesMonth = selectedHistoryMonth == null ||
          (selectedHistoryMonth!.year == now.year && selectedHistoryMonth!.month == now.month);
      if (matchesYear && matchesMonth) {
        payoutHistory.insert(
          0,
          PayoutHistoryDisplay(
            id: payoutId,
            amount: amount,
            status: 'pending',
            paymentMethod: selectedMethod,
            bankName: bankName,
            bankAccNo: bankAccNo,
            ewalletPhone: ewalletPhone,
            requestedAt: now,
            fee: fee,
          ),
        );
        if (_historyDatesLoaded) {
          _historyOffset += 1;
        }
      }
      _historyDates.add(now);

      return true;
    } on PostgrestException catch (e) {
      debugPrint('PayoutViewModel.submitPayout: PostgrestException ${e.code}: ${e.message}');
      errorMessage = e.message.toLowerCase().contains('balance')
          ? e.message
          : 'Could not process payout. Please try again.';
      return false;
    } catch (e) {
      debugPrint('PayoutViewModel.submitPayout: $e');
      errorMessage = 'Could not process payout. Please try again.';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> runPayoutStatusAnimation() async {
    final payoutId = lastPayoutId;
    if (payoutId == null) return;

    await for (final status in _gateway.process(payoutId)) {
      payoutStatus = status;
      _safeNotify();
      if (status != 'completed' && status != 'failed') continue;

      _syncHistoryStatus(payoutId, status);
      _safeNotify();

      try {
        await _service.updatePayoutStatus(payoutId, status);
        await _localService.updateCachedPayoutStatus(payoutId, status, processedAt: DateTime.now());
      } catch (e) {
        pendingReconciliation[payoutId] = status;
        var localSaveOk = true;
        try {
          await _localService.savePendingReconciliation(payoutId, status);
        } catch (localError) {
          localSaveOk = false;
          debugPrint('Failed to queue payout reconciliation for $payoutId: $localError');
        }
        debugPrint('Failed to persist payout status for $payoutId: $e');
        await Future.delayed(const Duration(seconds: 3));
        try {
          await _service.updatePayoutStatus(payoutId, status);
          await _localService.updateCachedPayoutStatus(payoutId, status, processedAt: DateTime.now());
          await _localService.removePendingReconciliation(payoutId);
          pendingReconciliation.remove(payoutId);
        } catch (e2) {
          if (!localSaveOk) {
            try {
              await _localService.savePendingReconciliation(payoutId, status);
            } catch (localError2) {
              debugPrint('Still failed to queue payout reconciliation for $payoutId: $localError2');
            }
          }
          debugPrint('Retry also failed to persist payout status for $payoutId: $e2');
        }
      }
    }
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
      ewalletPhone: old.ewalletPhone,
      requestedAt: old.requestedAt,
      fee: old.fee,
    );
  }
}