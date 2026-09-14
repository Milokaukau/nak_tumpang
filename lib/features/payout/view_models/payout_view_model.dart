import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/utils/validators.dart';
import 'package:nak_tumpang/features/payout/data/services/payout_gateway.dart';
import 'package:nak_tumpang/features/payout/data/services/payout_local_service.dart';
import 'package:nak_tumpang/features/payout/data/services/payout_service.dart';

enum PayoutMethod { bankTransfer, tngEwallet }

// fallback for live cases where payout_settings in supabase is not available
const double kFallbackBankTransferFee = 1.00;

// minimum amount for a payout, avoid rm1 payout that would return 0 when deducted the transfer fee
const double kMinPayoutAmount = 10.00;

// whole numbers only
final RegExp _amountFormatRegex = RegExp(r'^\d+$');

// pre-submission preview before a payout history exist
// should refer to payout_settings, not the fallback constant
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

// points shown as whole number
// floored, not rounded
// driver cant see a point figure bigger than the RM value
String pointsLabel(double amount) => amount.floor().toString();

extension PayoutMethodDb on PayoutMethod {
  // value stores in payout_history payment_method
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

  // fee charged at payout
  // only uses fallback transfer fee for older rows that predate the column
  double get resolvedFee => fee ?? (paymentMethod == PayoutMethod.bankTransfer ? kFallbackBankTransferFee : 0);

  double get netAmount {
    final net = amount - resolvedFee;
    return net < 0 ? 0 : net;
  }

  String get _destination => (isEwallet ? ewalletPhone : bankAccNo) ?? '-';

  // masked bank acc no and ewallet phone num besides the final 4 values
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
  PayoutViewModel({PayoutGateway? gateway}) : _gateway = gateway ?? MockPayoutGateway() {
    ewalletPhoneFocusNode.addListener(notifyListeners);
  }

  final _service = PayoutService();
  final _localService = PayoutLocalService();
  // Whatever actually processes the payout after it's recorded
  final PayoutGateway _gateway;

  bool isLoading = true;
  String? errorMessage;
  String? walletNotice;

  double totalEarnings = 0;
  double availableBalance = 0;
  double totalWithdrawn = 0;

  // starts at fallback so claim dialog can show if it's open before the fetch resolves
  // corrected the moment it resolved
  double bankTransferFee = kFallbackBankTransferFee;

  int tripsCompletedCount = 0;
  double thisMonthPoints = 0;
  List<RecentTripDisplay> recentTrips = [];

// tab toggle between history and wallet
  PayoutView currentView = PayoutView.wallet;
  bool isHistoryLoading = false;
  bool isLoadingMoreHistory = false;
  bool hasMoreHistory = true;
  String? historyError;
  // Non-fatal notice for the History tab (stale cache while offline) —
  // same reasoning as walletNotice: historyError means "nothing to
  // show", this means "showing something, but it's not fresh".
  String? historyNotice;
  List<PayoutHistoryDisplay> payoutHistory = [];

  static const int _historyPageSize = 20;
  int _historyOffset = 0;

  // every timestamp for this driver
  List<DateTime> _historyDates = [];
  bool _historyDatesLoaded = false;

  int? selectedHistoryYear;
  DateTime? selectedHistoryMonth;
  bool get hasAnyHistory => _historyDates.isNotEmpty;

  // first filter tier narrow history month before month chips can be picked from
  List<int> get historyYears {
    final years = _historyDates.map((d) => d.year).toSet().toList();
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  // only the history of the selected month will be shown
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
    // a month from a different year can no longer be valid once year filter changes
    selectedHistoryMonth = null;
    _reloadHistoryForCurrentScope();
  }

  void selectHistoryMonth(DateTime? month) {
    selectedHistoryMonth = month;
    _reloadHistoryForCurrentScope();
  }

// payout form state
  PayoutMethod selectedMethod = PayoutMethod.bankTransfer;
  final amountController = TextEditingController(text: '0');

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

  // payoutIds whose terminal status ('completed'/'failed') was decided
  // locally but failed to persist to payout_history — .g.see
  //   // runPayoutStatusAnimation(). Surfaced so a caller (e the History
  // screen, on next load) can retry the write instead of the DB silently
  // staying on 'pending' forever after the driver already saw "Paid".
  final Set<String> pendingReconciliation = {};

  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
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

  // fetches lightweight date list once then the first page for all
  Future<void> loadHistory() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    isHistoryLoading = true;
    historyError = null;
    historyNotice = null;
    notifyListeners();

    try {
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
        payoutHistory = cachedRows.map(PayoutHistoryDisplay.fromRow).toList();
        _historyOffset = payoutHistory.length;
        hasMoreHistory = false; // cache has no reliable "more pages" signal
        // Cached rows exist, so this is informational, not fatal — the
        // list, filters, and refresh all stay usable.
        historyNotice = "Showing your last saved history — you're offline.";
      } else {
        // Nothing to show at all — this is the one case that should
        // replace the whole tab with an error + retry.
        historyError = 'Could not load payout history. Please try again.';
      }
    } finally {
      isHistoryLoading = false;
      notifyListeners();
    }
  }

  // pull to refresh point so user dont need to exit page and return to see changes
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
        payoutHistory = cachedRows.map(PayoutHistoryDisplay.fromRow).toList();
        _historyOffset = payoutHistory.length;
        hasMoreHistory = false;
        historyNotice = "Showing your last saved history — you're offline.";
      } else {
        historyError = 'Could not load payout history. Please try again.';
      }
    } finally {
      isHistoryLoading = false;
      notifyListeners();
    }
  }

  // fetches the next page under the current scope and appends it
  Future<void> loadMoreHistory() async {
    if (isLoadingMoreHistory || isHistoryLoading || !hasMoreHistory) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    isLoadingMoreHistory = true;
    notifyListeners();
    try {
      await _fetchHistoryPage(userId, reset: false);
    } catch (e) {
      // driver can scroll or tap load more to retry without losing the page they already have
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
    payoutHistory = reset ? page : [...payoutHistory, ...page];
    _historyOffset += page.length;
    hasMoreHistory = page.length == _historyPageSize;
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
        // Cached data exists, so this is informational, not fatal (the wallet, toggle, and refresh all stay usable).
        walletNotice = "Showing your last saved wallet — you're offline.";
      } else {
        // nothing to show
        errorMessage = 'Could not load wallet. Please try again.';
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
      // The wallet is already populated from the previous successful
      // load — a failed refresh is never fatal here, just a banner.
      walletNotice = 'Could not refresh wallet. Please try again.';
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

    // Best-effort: if this fails, bankTransferFee just stays at its
    // fallback value rather than blocking the whole Wallet tab from
    // loading over what's ultimately a display-only preview number.
    try {
      bankTransferFee = await _service.fetchBankTransferFee();
      await _localService.cacheBankTransferFee(bankTransferFee);
    } catch (_) {
      // keep the fallback already assigned above
    }

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(
      now.month == 12 ? now.year + 1 : now.year,
      now.month == 12 ? 1 : now.month + 1,
      1,
    );

    // Two bounded queries instead of one unpaginated fetch of every
    // completed trip the driver has ever had: one scoped to the current
    // month (for the stat cards), one capped at 10 rows (for the
    // "Recent trips" list) — same reasoning as payout_history's
    // paginated fetch, so this doesn't get slower the longer a driver's
    // been active.
    final monthTrips = await _service.fetchCompletedTripsInRange(
      userId,
      start: monthStart,
      end: monthEnd,
    );
    thisMonthPoints = 0;
    // Kept in lockstep with thisMonthPoints — both describe the same
    // current-month window, so the stat cards never show a trip count
    // that doesn't actually back up the points figure next to it.
    tripsCompletedCount = 0;
    for (final trip in monthTrips) {
      thisMonthPoints += (trip['fee'] as num?)?.toDouble() ?? 0;
      tripsCompletedCount++;
    }

    final recent = await _service.fetchRecentCompletedTrips(userId, limit: 10);
    recentTrips = recent.map((trip) {
      final dateStr = trip['sub_start_date'] as String?;
      final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
      final passengerName = trip['passenger_trips']?['users']?['name'] as String? ?? 'Passenger';
      return RecentTripDisplay(
        tripId: trip['id']?.toString() ?? '-',
        passengerName: passengerName,
        pickupName: trip['pickup_name'] as String? ?? '-',
        dropoffName: trip['dropoff_name'] as String? ?? '-',
        points: (trip['fee'] as num?)?.toDouble() ?? 0,
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

  /// Fills the amount field with the full available balance — the "Max"
  /// shortcut next to the field, since the field itself no longer
  /// defaults to the full balance.
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

  /// no cents
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

// clears screen when driver goes back to select payment method or change amount
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
    // Guards against a second call landing while one is already in
    // flight (e.g. a double-tap that lands before the UI has rebuilt
    // with isSubmitting/isLoading disabling the button) — this moves
    // real balance, so don't rely on the button's disabled state alone.
    if (isSubmitting) return false;

    // Evaluated as two separate calls (not `!validateAmount() ||
    // !validateDetails()`) so both always run — a `||` short-circuit
    // would skip validateDetails() whenever the amount is invalid,
    // leaving bank/eWallet field errors stale on screen.
    final amountValid = validateAmount();
    final detailsValid = validateDetails();
    if (!amountValid || !detailsValid) {
      return false;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    final amount = double.parse(amountController.text.trim());

    // e-wallet payouts have no bank, bank_name goes in as null
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
        // request_payout() already committed by the time it returns —
        // the balance deduction and payout_history insert happen inside
        // its own server-side transaction, before this JSON payload is
        // even built. So an unexpected shape here doesn't mean the
        // payout failed — it means it likely succeeded but this
        // response can't be trusted to reflect it. Falling through to
        // the generic "please try again" message would risk the driver
        // retrying and being deducted twice for a payout that already
        // went through, so refresh from the server instead of guessing.
        debugPrint('PayoutViewModel.submitPayout: unexpected request_payout result shape: $result');
        errorMessage = "Your payout may have gone through, but we couldn't confirm it here — "
            'pull to refresh before trying again.';
        await refreshWallet();
        await refreshHistory();
        return false;
      }

      final payoutId = rawPayoutId;
      availableBalance = rawNewBalance.toDouble();
      // The server computes and stores the fee now (see request_payout,
      // reading payout_settings.bank_transfer_fee) — use exactly what it
      // returns rather than recomputing it here, so the optimistic local
      // entry can't ever disagree with what actually got written to
      // payout_history.
      final fee = (result['fee'] as num?)?.toDouble();
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
        'fee': fee ?? 0,
      });

      // Only splice the new entry directly into the currently-loaded page
      // if it actually belongs to whatever scope is selected right now
      // (almost always true, since a fresh payout is dated today — but
      // if the driver happened to have an old year/month filter active,
      // inserting it here would show a \"today\" row inside a \"March 2025\"
      // filtered list, which would be wrong).
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
        // This new row now sits at position 0 in the server's own
        // requested_at-desc order too, pushing every row after it one
        // position later. _historyOffset is a count of rows already
        // fetched from the server under the old order, so it needs the
        // same +1 shift — otherwise the next loadMoreHistory() page would
        // start one position too early and re-fetch (and re-append) a row
        // that's already in the list, showing it twice.
        if (_historyDatesLoaded) {
          _historyOffset += 1;
        }
      }
      // Keep the filter-chip date list in sync too — otherwise a payout
      // made in a year/month that isn't already in _historyDates
      // wouldn't get a chip for it until the next full reload.
      _historyDates.add(now);

      return true;
    } on PostgrestException catch (e) {
      // request_payout raises a plain, driver-facing message for the
      // one expected case (stale cached balance) — pass that through
      // as-is. Anything else (constraint violations, unexpected server
      // errors, etc.) shouldn't leak raw DB error text to the driver,
      // but IS worth seeing in the console while debugging.
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

  // status transitions come from the (currently mocked) payout gateway.
  // 'processing' is UI-only — see the payoutStatusLabel/Color doc
  // comment above for why it's never written to payout_history.
  //
  // Both payment methods run this and auto-complete — see
  // MockPayoutGateway's doc comment for why that's a deliberate demo
  // simplification rather than a claim that real bank transfers clear
  // instantly.
  Future<void> runPayoutStatusAnimation() async {
    final payoutId = lastPayoutId;
    if (payoutId == null) return;

    payoutStatus = 'pending';
    _safeNotify();

    await for (final status in _gateway.process(payoutId)) {
      if (_disposed) return;
      payoutStatus = status;
      final isTerminal = status == 'completed' || status == 'failed';
      // Mutate payoutHistory *before* the first notify for a terminal
      // status, so the one rebuild this triggers already reflects the
      // synced entry — this is also the last emission from the stream,
      // so there's no later notify that would otherwise pick it up and
      // the History tab would stay stuck showing "Pending".
      if (isTerminal) {
        _syncHistoryStatus(payoutId, status);
      }
      _safeNotify();
      if (isTerminal) {
        try {
          await _service.updatePayoutStatus(payoutId, status);
          await _localService.updateCachedPayoutStatus(payoutId, status, processedAt: DateTime.now());
        } catch (e) {
          // The UI already shows this payout as done — don't let a
          // failed write silently leave payout_history disagreeing with
          // what the driver saw. Flag it for reconciliation and retry
          // once, rather than losing the failure entirely.
          pendingReconciliation.add(payoutId);
          debugPrint('Failed to persist payout status for $payoutId: $e');
          await Future.delayed(const Duration(seconds: 3));
          try {
            await _service.updatePayoutStatus(payoutId, status);
            await _localService.updateCachedPayoutStatus(payoutId, status, processedAt: DateTime.now());
            pendingReconciliation.remove(payoutId);
          } catch (e2) {
            debugPrint('Retry also failed to persist payout status for $payoutId: $e2');
          }
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