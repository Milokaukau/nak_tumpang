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
  final String tripId; // payments.id (settled) — shown as a reference on the receipt
  final String passengerName;
  final String tripName; // the driver's own trip name this cycle was billed against
  final String pickupName;
  final String dropoffName;
  final double points; // net, after platform fee — what actually hit the wallet
  final double grossAmount; // what the passenger paid, before the platform fee
  final double platformFee;
  final double dailyFee; // tumpang_subscription.fee — the per-day rate for this ride
  final DateTime? cycleStartDate;
  final DateTime? cycleEndDate;
  final String monthLabel; // e.g. "August"
  final DateTime? tripDate; // full date, for the trip detail popup

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

  // Billed days derived from amount ÷ daily rate rather than the raw
  // cycle_start/cycle_end span — grossAmount already has driver-caused
  // missed days deducted (see _countDriverMissedDays), the raw date range
  // doesn't, so recomputing from dates alone would overcount.
  int get billableDays => dailyFee > 0 ? (grossAmount / dailyFee).round() : 0;
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

  // Count of settled payment rows (billing cycles) this month, not
  // individual ride days — see _loadWalletData for why. Backs the
  // "Payments this month" stat card.
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

  // payoutId -> intended terminal status ('completed'/'failed'), for
  // payouts whose status was decided locally but failed to persist to
  // payout_history — see runPayoutStatusAnimation(). Backed by
  // PayoutLocalService's pending_payout_reconciliation table so a
  // pending record survives an app restart, not just this instance.
  // Consumed by _applyPendingReconciliations(), which loadHistory() and
  // refreshHistory() both call before trusting a freshly-fetched server
  // status for the same payout — otherwise a stale server 'pending' row
  // could silently overwrite the terminal status the driver already saw.
  Map<String, String> pendingReconciliation = {};

  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // NetworkService's device-level connectivity flag (see
  // core/services/network_service.dart) is what we tried first, but it
  // can misreport — some emulators/simulators, VPNs, and corporate
  // networks confuse connectivity_plus, and it can lag right after
  // reconnecting. What actually tells us whether the driver is offline
  // is the exception the failed request threw: a PostgrestException or
  // AuthException means the request reached Supabase and got a real
  // response back (so the device is online, whatever else went wrong);
  // only a genuine network failure — no route to host, DNS failure,
  // timeout — means the driver is actually offline.
  bool _isConnectivityError(Object error) =>
      error is SocketException || error is TimeoutException || error is http.ClientException;

  String _fetchFailureMessage(Object error, {required String whenOffline, required String whenOnline}) {
    // Raw error no longer shown in the UI — it's still logged via the
    // debugPrint calls at each catch site, which is enough to diagnose
    // issues without exposing stack-trace-shaped text to drivers.
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

  // fetches lightweight date list once then the first page for all
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
        hasMoreHistory = false; // cache has no reliable "more pages" signal
        // Cached rows exist, so this is informational, not fatal — the
        // list, filters, and refresh all stay usable.
        historyNotice = _fetchFailureMessage(
          e,
          whenOffline: "Showing your last saved history — you're offline.",
          whenOnline: 'Could not load the latest history — showing your last saved version.',
        );
      } else {
        // Nothing to show at all — this is the one case that should
        // replace the whole tab with an error + retry.
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
    // A row here reflects whatever Supabase currently has for it. If
    // that payout still has an unresolved local reconciliation (the
    // write that would've updated it on the server hasn't gone through
    // yet), the server's copy is stale — keep showing the terminal
    // status the driver already saw locally instead of regressing it
    // back to 'pending'.
    final reconciled = _applyReconciliationOverlay(page);
    payoutHistory = reset ? reconciled : [...payoutHistory, ...reconciled];
    _historyOffset += page.length;
    hasMoreHistory = page.length == _historyPageSize;
  }

  // Overlays any pending local reconciliation status onto a list of rows,
  // leaving rows without one untouched. Shared by _fetchHistoryPage (server
  // rows) and the offline-cache fallbacks in loadHistory() and
  // _reloadHistoryForCurrentScope(), so a cached 'pending' row can't show
  // through stale just because it came from the cache instead of the server.
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

  // Retries any payout statuses that were decided locally but never made
  // it into payout_history (see runPayoutStatusAnimation). Runs before
  // loadHistory()/refreshHistory() trust a freshly-fetched server status,
  // so a payout the driver already saw as "Paid"/"Failed" doesn't get
  // silently shown as "Pending" again just because the write that would've
  // confirmed it on the server hadn't landed yet.
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
        // Still unresolved — keep it queued (both in memory and in the
        // local table) for the next attempt, and _fetchHistoryPage will
        // keep overriding this payout's row with `status` until then.
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
        // The balance alone isn't the whole Wallet tab — "Recent
        // transactions" and the two stat boxes sit right under it and
        // used to come back empty offline because nothing restored them
        // here. Best-effort: a cache miss just leaves the list empty,
        // exactly as before, rather than turning a usable offline
        // wallet into the no-cache error branch below.
        try {
          await _loadWalletDataFromCache(userId);
        } catch (cacheError) {
          debugPrint('load(): failed to restore wallet trips from cache: $cacheError');
        }
        // Cached data exists, so this is informational, not fatal (the wallet, toggle, and refresh all stay usable).
        walletNotice = _fetchFailureMessage(
          e,
          whenOffline: "Showing your last saved wallet — you're offline.",
          whenOnline: 'Could not load the latest wallet — showing your last saved version.',
        );
      } else {
        // nothing to show
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
      // The wallet is already populated from the previous successful
      // load — a failed refresh is never fatal here, just a banner.
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
    // current-month window. Note this counts settled payment rows
    // (billing cycles), not individual ride days — a single row can
    // cover several billed days (amount = dailyFee × billableDays,
    // see payment_supabase_service.dart), so the UI label reads
    // "Payments this month", not "Trips this month".
    tripsCompletedCount = 0;
    for (final trip in monthTrips) {
      // driver_net_amount is set by settle_payments() — the invoice
      // amount with the RM1 platform fee already deducted.
      thisMonthPoints += (trip['driver_net_amount'] as num?)?.toDouble() ?? 0;
      tripsCompletedCount++;
    }

    final recent = await _service.fetchRecentCompletedTrips(userId, limit: 10);
    recentTrips = recent.map((trip) {
      // paid_at (when it actually posted to the wallet) rather than
      // cycle_start_date, so "recent" ordering matches what actually
      // credited the driver.
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

    // Mirror both result sets into SQLite so an offline load() can
    // restore the "Recent transactions" list and the stat boxes, the
    // same way the History tab already restores from payout_history.
    // Best-effort and last: a cache write failing must never make an
    // otherwise-successful wallet load look broken.
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

  /// Rebuilds [recentTrips] and the two stat-box values from SQLite.
  /// Used by the offline fallback in [load] — the rows were flattened on
  /// the way in (see PayoutLocalService.cacheDriverWalletTrips), so this
  /// reads the display columns directly instead of re-walking the
  /// Supabase join shape.
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
        await refreshWallet();
        await refreshHistory();
        // refreshWallet() clears walletNotice on success, so this has to
        // be set after both refreshes — otherwise a successful refresh
        // would wipe it before the driver ever sees it. Kept out of
        // errorMessage on purpose: driver_balance_screen.dart replaces
        // the whole wallet/history view with errorMessage, and the
        // payout very likely went through, so the tabs (and their
        // refresh controls) need to stay visible.
        walletNotice = "Your payout may have gone through, but we couldn't confirm it here — "
            'pull to refresh before trying again.';
        notifyListeners();
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
      // payout_history.fee is REAL NOT NULL DEFAULT 0, and
      // PayoutHistoryDisplay.resolvedFee falls back to
      // kFallbackBankTransferFee for bank transfers when fee is null.
      // Write that same fallback to the cache rather than a bare 0, so
      // an offline reload doesn't compute a different (too-high)
      // netAmount than what the driver saw live.
      final cachedFee = fee ?? (selectedMethod == PayoutMethod.bankTransfer ? kFallbackBankTransferFee : 0);
      lastPayoutId = payoutId;
      // Explicit reset, not just relying on the field's initial value —
      // this view model is long-lived (one instance per driver session,
      // not per-dialog), so a previous payout could've already left this
      // at 'completed'. runPayoutStatusAnimation() (called once the
      // success dialog is on screen) drives it from here through the
      // gateway's processing -> completed animation.
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

  // Drives the pending -> processing -> completed animation on the
  // success dialog by consuming the (currently mocked) payout gateway's
  // status stream — see MockPayoutGateway's doc comment for why this is
  // a deliberate demo simplification. 'processing' is UI-only and never
  // written to payout_history (see payoutStatusLabel/Color); only the
  // terminal 'completed'/'failed' status gets persisted, with the same
  // retry/reconciliation safety net as before in case that write fails.
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
        // The UI already shows this payout as done — don't let a failed
        // write silently leave payout_history disagreeing with what the
        // driver saw. Flag it for reconciliation and retry once, rather
        // than losing the failure entirely.
        pendingReconciliation[payoutId] = status;
        // Local persistence is independent of the remote retry below — a
        // database error here (e.g. sqflite hiccup) must not skip the
        // immediate remote retry, which is the more time-sensitive of the two.
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
          // Still unresolved after the immediate retry — it needs to stay
          // recorded in pending_payout_reconciliation so
          // _applyPendingReconciliations can retry it later (including
          // across app restarts). If the earlier local save above failed,
          // that record was never written, so try once more here rather
          // than silently losing the reconciliation.
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