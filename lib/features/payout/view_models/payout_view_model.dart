import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/utils/validators.dart';
import 'package:nak_tumpang/features/payout/data/services/payout_gateway.dart';
import 'package:nak_tumpang/features/payout/data/services/payout_service.dart';

enum PayoutMethod { bankTransfer, tngEwallet }

/// Fallback used only for two narrow cases where a live value from
/// payout_settings isn't available: (1) briefly, before load() finishes
/// its first fetch, and (2) PayoutHistoryDisplay.resolvedFee's fallback
/// for payout_history rows that predate the `fee` column entirely (all
/// of which were backfilled to exactly this value — see
/// migration_add_payout_fee.sql). It is NOT what request_payout()
/// charges — that reads payout_settings.bank_transfer_fee at request
/// time, which is the actual single source of truth and can be changed
/// without touching this app's code at all.
const double kFallbackBankTransferFee = 1.00;

/// Smallest amount a driver can request in one payout. Mainly guards
/// against a near-zero request that a flat RM1 bank transfer fee would
/// wipe out (or exceed) — e.g. requesting RM0.50 nets RM0 after the fee.
const double kMinPayoutAmount = 10.00;

/// Whole numbers only — payouts can't be requested in cents. Matches
/// "50" but rejects "50.5", "50.00", and any non-numeric junk that
/// double.tryParse would otherwise silently round away.
final RegExp _amountFormatRegex = RegExp(r'^\d+$');

/// Pre-submission preview only (claim/success dialogs, before a
/// payout_history row exists to read an actual stored fee from).
/// [bankTransferFee] should be PayoutViewModel.bankTransferFee — the
/// live value fetched from payout_settings — not the fallback constant,
/// so the preview always matches whatever request_payout() will
/// actually charge.
double payoutNetAmount(double grossAmount, PayoutMethod method, double bankTransferFee) =>
    method == PayoutMethod.bankTransfer
        ? (grossAmount - bankTransferFee < 0 ? 0 : grossAmount - bankTransferFee)
        : grossAmount;

/// payout_history.status only allows 'pending' | 'completed' | 'failed'
/// (a DB CHECK constraint — see request_payout.sql). 'processing' is a
/// transient, UI-only value that PayoutViewModel.payoutStatus can hold
/// mid-animation but never writes to the DB.
///
/// 'Paid' reads better than 'Completed' for a payout specifically, so
/// that's what's shown for the 'completed' status — this is purely
/// display wording, the stored value is still 'completed'. Shared here
/// so the wallet screen, the history detail dialog, and the payout
/// success dialog can't drift out of sync with each other.
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

/// Points are always shown as a whole number, floored rather than
/// rounded — a driver should never see a points figure bigger than the
/// RM value it maps to (rounding up, e.g. 250.50 -> "251 pts" next to
/// "RM250.50", looked like two different balances).
String pointsLabel(double amount) => amount.floor().toString();

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
  final String? bankAccNo;
  final String? ewalletPhone;
  final DateTime? requestedAt;
  // Nullable because rows created before the `fee` column existed have
  // none stored — resolvedFee below falls back to the old compile-time
  // calculation for exactly those legacy rows.
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

  /// The fee actually charged on this payout. Uses the stored value when
  /// present (every payout made after the fee column was added); falls
  /// back to [kFallbackBankTransferFee] only for older rows that predate
  /// the column (all of which were backfilled to that exact value).
  double get resolvedFee => fee ?? (paymentMethod == PayoutMethod.bankTransfer ? kFallbackBankTransferFee : 0);

  /// [amount] minus [resolvedFee], floored at 0.
  double get netAmount {
    final net = amount - resolvedFee;
    return net < 0 ? 0 : net;
  }

  /// The raw destination value for this payout — [bankAccNo] for a bank
  /// transfer, [ewalletPhone] for e-wallet. Never both: request_payout()
  /// only ever writes one of the two columns, matching [paymentMethod].
  String get _destination => (isEwallet ? ewalletPhone : bankAccNo) ?? '-';

  /// [_destination] with everything but the last 4 characters hidden
  /// behind dots, for display in a persistent history list — e.g.
  /// "•••• 5521". Short values (4 characters or fewer) are masked in
  /// full rather than shown outright, since there'd be nothing
  /// meaningful left hidden.
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
  // Whatever actually processes the payout after it's recorded — see
  // payout_gateway.dart for why this is still a mock and how to swap it.
  final PayoutGateway _gateway;

  bool isLoading = true;
  String? errorMessage;

  double totalEarnings = 0;
  double availableBalance = 0;
  double totalWithdrawn = 0;

  // Fetched from payout_settings in load() — starts at the fallback so
  // the claim dialog has something reasonable to show if it's opened
  // before that fetch resolves, but is corrected the moment it does.
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
  List<PayoutHistoryDisplay> payoutHistory = [];

  static const int _historyPageSize = 20;
  int _historyOffset = 0;

  // Every requested_at timestamp for this driver (id/amount/etc not
  // included — see PayoutService.fetchPayoutHistoryDates). Loaded once,
  // separately from the paginated rows below, purely so the year/month
  // filter chips can show every year/month that actually has payouts in
  // it without requiring the driver's entire history to be loaded first.
  List<DateTime> _historyDates = [];
  bool _historyDatesLoaded = false;

  // null = "All" — no year filter applied to the History tab.
  int? selectedHistoryYear;
  // null = "All" — no month filter applied (always scoped within
  // selectedHistoryYear when that's also set).
  DateTime? selectedHistoryMonth;

  /// Whether this driver has *any* payout history at all, independent of
  /// whatever year/month is currently selected — used to decide whether
  /// to show the History tab's empty state or its filter chips. Backed
  /// by [_historyDates] (loaded once, in full) rather than [payoutHistory]
  /// (now just the current scope's page), so filtering to a month with
  /// zero results doesn't get mistaken for "no history at all".
  bool get hasAnyHistory => _historyDates.isNotEmpty;

  /// Distinct years present in the driver's payout history, newest
  /// first. First filter tier on the History tab — narrows
  /// [historyMonths] before the month chips are picked from.
  List<int> get historyYears {
    final years = _historyDates.map((d) => d.year).toSet().toList();
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  /// Distinct year-month values present in the driver's payout history,
  /// newest first — scoped to [selectedHistoryYear] when one is picked,
  /// so the month row only ever shows months within that year instead of
  /// every month across a driver's whole history at once.
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

  /// The currently loaded page(s) of payout rows for whatever scope is
  /// selected. Unlike the old client-side filter, [selectHistoryYear] and
  /// [selectHistoryMonth] now trigger a fresh, server-scoped fetch rather
  /// than filtering an already-fully-loaded list — so [payoutHistory]
  /// itself is always already "the filtered list". Kept as a getter
  /// (rather than renaming every call site) so nothing else needs to
  /// change.
  List<PayoutHistoryDisplay> get filteredPayoutHistory => payoutHistory;

  void selectHistoryYear(int? year) {
    selectedHistoryYear = year;
    // A month from a different year can no longer be valid once the
    // year filter changes — always reset back to "All months" here
    // rather than leaving a stale, now-invisible month selected.
    selectedHistoryMonth = null;
    _reloadHistoryForCurrentScope();
  }

  void selectHistoryMonth(DateTime? month) {
    selectedHistoryMonth = month;
    _reloadHistoryForCurrentScope();
  }

// payout form state
  PayoutMethod selectedMethod = PayoutMethod.bankTransfer;
  // Defaults to '0' rather than empty or the full balance, so the field
  // always shows a concrete starting amount next to the always-visible
  // 'RM' prefix.
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
  // locally but failed to persist to payout_history — see
  // runPayoutStatusAnimation(). Surfaced so a caller (e.g. the History
  // screen, on next load) can retry the write instead of the DB silently
  // staying on 'pending' forever after the driver already saw "Paid".
  final Set<String> pendingReconciliation = {};

  bool _disposed = false;

  /// Guards notifyListeners() calls made from inside async work (like
  /// runPayoutStatusAnimation's awaited delays) that may still be
  /// in-flight after this ViewModel has been disposed — calling
  /// notifyListeners() post-dispose throws.
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
    // Gate on _historyDatesLoaded rather than payoutHistory.isEmpty: a
    // driver who claims a payout before ever opening this tab gets an
    // optimistic row spliced into payoutHistory (see submitPayout), which
    // would make it non-empty and skip the real loadHistory() call below.
    // hasMoreHistory then defaults to true, so "Load more" would append a
    // freshly-fetched page — that already contains that same row — right
    // after the optimistic one, showing it twice. Checking the dates flag
    // instead means the very first tab visit always does a full
    // loadHistory(), which fetches page 1 as a clean replace, not an
    // append, so the optimistic row is folded in exactly once.
    if (view == PayoutView.history && !_historyDatesLoaded && historyError == null) {
      loadHistory();
    }
  }

  /// Initial load for the History tab: fetches the lightweight date list
  /// (for the filter chips) once, then the first page of the "All" scope.
  Future<void> loadHistory() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    isHistoryLoading = true;
    historyError = null;
    notifyListeners();

    try {
      if (!_historyDatesLoaded) {
        _historyDates = await _service.fetchPayoutHistoryDates(userId);
        _historyDatesLoaded = true;
      }
      await _fetchHistoryPage(userId, reset: true);
    } catch (e) {
      historyError = 'Could not load payout history. Please try again.';
    } finally {
      isHistoryLoading = false;
      notifyListeners();
    }
  }

  /// Public pull-to-refresh entry point for the History tab — re-fetches
  /// the currently selected year/month scope from scratch, so a status
  /// change made outside the app (e.g. the bank-payout auto-settle cron
  /// job) shows up without the driver having to leave and re-enter this
  /// screen.
  Future<void> refreshHistory() => _reloadHistoryForCurrentScope();

  /// Re-fetches from scratch under whatever year/month is now selected —
  /// called whenever the filter changes rather than filtering an
  /// already-loaded list, since the list itself is no longer guaranteed
  /// to contain every row for the new scope.
  Future<void> _reloadHistoryForCurrentScope() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    isHistoryLoading = true;
    historyError = null;
    payoutHistory = [];
    notifyListeners();

    try {
      await _fetchHistoryPage(userId, reset: true);
    } catch (e) {
      historyError = 'Could not load payout history. Please try again.';
    } finally {
      isHistoryLoading = false;
      notifyListeners();
    }
  }

  /// Fetches the next page under the current scope and appends it. Safe
  /// to call from a "Load more" button or a scroll-end listener; a no-op
  /// while a fetch is already in flight or once the scope is exhausted.
  Future<void> loadMoreHistory() async {
    if (isLoadingMoreHistory || isHistoryLoading || !hasMoreHistory) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    isLoadingMoreHistory = true;
    notifyListeners();
    try {
      await _fetchHistoryPage(userId, reset: false);
    } catch (e) {
      // Leave whatever's already loaded on screen; the driver can just
      // scroll/tap "Load more" again to retry rather than losing the
      // page they already have.
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
    notifyListeners();

    try {
      await _loadWalletData(userId);
    } catch (e) {
      errorMessage = 'Could not load wallet. Please try again.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Re-fetches balance/earnings/recent trips without the full-screen
  /// loading spinner load() shows — used for pull-to-refresh on the
  /// Wallet tab, where the existing content should stay visible (with
  /// RefreshIndicator's own spinner up top) rather than being replaced.
  Future<void> refreshWallet() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _loadWalletData(userId);
    } catch (e) {
      errorMessage = 'Could not refresh wallet. Please try again.';
    } finally {
      notifyListeners();
    }
  }

  Future<void> _loadWalletData(String userId) async {
    final profile = await _service.fetchDriverProfile(userId);
    totalEarnings = (profile?['total_earnings'] as num?)?.toDouble() ?? 0;
    availableBalance = (profile?['available_balance'] as num?)?.toDouble() ?? 0;
    totalWithdrawn = (profile?['total_withdrawn'] as num?)?.toDouble() ?? 0;

    // Best-effort: if this fails, bankTransferFee just stays at its
    // fallback value rather than blocking the whole Wallet tab from
    // loading over what's ultimately a display-only preview number.
    try {
      bankTransferFee = await _service.fetchBankTransferFee();
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

  /// Rounds a RM amount to the nearest cent, as an integer cent count.
  /// Used instead of comparing raw doubles: [setAmountToMax] round-trips
  /// availableBalance through toStringAsFixed(2) -> double.tryParse, and
  /// a direct `>` comparison on the resulting doubles can occasionally
  /// flag the reparsed value as infinitesimally larger than the
  /// original (floating-point representation, not an actual amount
  /// difference) — which would incorrectly block the driver's own "Max"
  /// shortcut. Comparing whole cents sidesteps that.
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
      final payoutId = result['payout_id'] as String;
      availableBalance = (result['new_balance'] as num).toDouble();
      // The server computes and stores the fee now (see request_payout,
      // reading payout_settings.bank_transfer_fee) — use exactly what it
      // returns rather than recomputing it here, so the optimistic local
      // entry can't ever disagree with what actually got written to
      // payout_history.
      final fee = (result['fee'] as num?)?.toDouble();
      lastPayoutId = payoutId;
      payoutStatus = 'pending';

      // Only splice the new entry directly into the currently-loaded page
      // if it actually belongs to whatever scope is selected right now
      // (almost always true, since a fresh payout is dated today — but
      // if the driver happened to have an old year/month filter active,
      // inserting it here would show a "today" row inside a "March 2025"
      // filtered list, which would be wrong).
      final now = DateTime.now();
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
      // errors, etc.) shouldn't leak raw DB error text to the driver.
      errorMessage = e.message.toLowerCase().contains('balance')
          ? e.message
          : 'Could not process payout. Please try again.';
      return false;
    } catch (e) {
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