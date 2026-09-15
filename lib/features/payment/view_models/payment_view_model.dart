import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/payment.dart';
import 'package:nak_tumpang/features/payment/data/services/payment_supabase_service.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/payment/data/services/payment_local_service.dart';

class PaymentViewModel extends ChangeNotifier {
  final PaymentSupabaseService _service = PaymentSupabaseService();
  final SupabaseClient _supabase = Supabase.instance.client;
  final PaymentLocalService _localService = PaymentLocalService();
  late final StreamSubscription<AuthState> _authSubscription;

  List<Payment> pendingPayments = [];
  List<Payment> paymentHistory = [];
  Set<String> selectedPaymentIds = {};

  bool isLoading = false;
  bool isLoadingProforma = false;
  bool isProcessingPayment = false;
  String? errorMessage;
  String? paymentErrorMessage;
  String? proformaErrorMessage;

  String? _currentUserId;

  bool get isOffline => NetworkService.isOfflineNotifier.value;

  PaymentViewModel() {
    _currentUserId = _supabase.auth.currentSession?.user.id;
    _initSession();
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) async {
      final newUserId = data.session?.user.id;

      // An explicit sign-out, or a DIFFERENT account signing in without an
      // app restart in between — either way the SQLite payments cache
      // still holds the PREVIOUS account's invoices/history and must not
      // leak into the new session.
      final isAccountChange = data.event == AuthChangeEvent.signedOut ||
          (data.event == AuthChangeEvent.signedIn && _currentUserId != null && newUserId != _currentUserId);

      if (isAccountChange) {
        try {
          await _localService.clearPaymentsCache();
        } catch (e) {
          debugPrint('Failed to clear local payments cache on account change: $e');
        }
        pendingPayments = [];
        paymentHistory = [];
        selectedPaymentIds.clear();
      }

      _currentUserId = newUserId;
      _initSession();
    });
  }

  /// Call this from your auth/logout flow as an extra safeguard so the
  /// cache is cleared immediately, without waiting for the
  /// onAuthStateChange event to round-trip.
  Future<void> clearLocalCacheOnLogout() async {
    try {
      await _localService.clearPaymentsCache();
    } catch (e) {
      debugPrint('Failed to clear local payments cache on logout: $e');
    }
    pendingPayments = [];
    paymentHistory = [];
    selectedPaymentIds.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _initSession() {
    final session = _supabase.auth.currentSession;
    _currentUserId = session?.user.id;
    if (session != null) {
      errorMessage = null;
      fetchAllPayments();
    } else {
      pendingPayments.clear();
      paymentHistory.clear();
      selectedPaymentIds.clear();
      notifyListeners();
    }
  }

  double get totalSelectedAmount {
    return pendingPayments
        .where((p) => selectedPaymentIds.contains(p.id))
        .fold(0.0, (sum, item) => sum + item.amount);
  }

  Future<void> fetchAllPayments() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        isLoading = false;
        notifyListeners();
        return;
      }

      if (isOffline) {
        // Read from SQLite
        final pRows = await _localService.getOfflinePayments(isCompleted: false);
        final cRows = await _localService.getOfflinePayments(isCompleted: true);

        pendingPayments = pRows.map((r) => Payment.fromJson(r)).toList();
        paymentHistory = cRows.map((r) => Payment.fromJson(r)).toList();
      } else {
        // Fetch from Supabase
        await _service.generateDueInvoicesForUser(userId);

        // fetchPendingPayments also repairs/cleans up invalid invoices
        // remotely (premature bills, zeroed-out amounts) and hands back
        // which invoice ids it deleted so the offline cache can be kept
        // in sync.
        final pendingResult = await _service.fetchPendingPayments(userId);
        pendingPayments = pendingResult.payments;
        paymentHistory = await _service.fetchPaymentHistory(userId);

        // Purge any zombie invoices the service just deleted server-side so
        // they don't resurface from the offline cache next time the app is
        // opened without a network connection.
        if (pendingResult.deletedInvoiceIds.isNotEmpty) {
          try {
            await _localService.deletePaymentsByIds(pendingResult.deletedInvoiceIds);
          } catch (e) {
            debugPrint('Failed to purge zombie invoices from local cache: $e');
          }
        }

        // Safely cache to SQLite without crashing UI on foreign key violations
        try {
          final allPayments = [...pendingPayments, ...paymentHistory].map((p) => p.toJson()).toList();
          await _localService.cachePayments(allPayments);
        } catch (e) {
          debugPrint('Could not cache payments offline due to strict foreign keys: $e');
        }
      }

      selectedPaymentIds.removeWhere((id) => !pendingPayments.any((p) => p.id == id));
    } catch (e) {
      errorMessage = 'Failed to load payments: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> loadProformaInvoiceDetails({
    required String subscriptionId,
    DateTime? cycleStart,
    DateTime? cycleEnd,
  }) async {
    isLoadingProforma = true;
    proformaErrorMessage = null;
    notifyListeners();
    try {
      return await _service.fetchProformaInvoiceDetails(
        subscriptionId: subscriptionId,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
      );
    } catch (e) {
      proformaErrorMessage = 'Some invoice details could not be loaded.';
      return null;
    } finally {
      isLoadingProforma = false;
      notifyListeners();
    }
  }

  void toggleSelection(String id) {
    if (selectedPaymentIds.contains(id)) {
      selectedPaymentIds.remove(id);
    } else {
      selectedPaymentIds.add(id);
    }
    notifyListeners();
  }

  void selectAll() {
    if (selectedPaymentIds.length == pendingPayments.length) {
      selectedPaymentIds.clear();
    } else {
      selectedPaymentIds = pendingPayments.map((p) => p.id).toSet();
    }
    notifyListeners();
  }

  Future<bool> paySelectedWithStripe() async {
    if (isOffline) {
      paymentErrorMessage = 'Payment cannot be processed offline.';
      notifyListeners();
      return false;
    }
    if (selectedPaymentIds.isEmpty) return false;

    isProcessingPayment = true;
    paymentErrorMessage = null;
    notifyListeners();

    try {
      final response = await _supabase.functions.invoke(
        'create-payment-intent',
        body: {
          'amount': totalSelectedAmount,
          'currency': 'myr',
          'description': 'Nak Tumpang Invoice Settlement (${selectedPaymentIds.length} items)',
        },
      );

      if (response.status != 200 || response.data == null) {
        final err = response.data is Map ? response.data['error'] : null;
        throw Exception(err ?? 'Stripe PaymentIntent failure.');
      }

      final paymentIntent = response.data as Map;
      final clientSecret = paymentIntent['client_secret'];
      if (clientSecret == null) {
        throw Exception('No client_secret returned from server');
      }

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Nak Tumpang',
          style: ThemeMode.light,
          billingDetails: const BillingDetails(
            address: Address(
              country: 'MY',
              city: '',
              line1: '',
              line2: '',
              postalCode: '',
              state: '',
            ),
          ),
        ),
      );

      await Stripe.instance.presentPaymentSheet();

      await _service.completePaymentBatch(selectedPaymentIds.toList());
      selectedPaymentIds.clear();
      await fetchAllPayments();
      return true;
    } on StripeException catch (e) {
      debugPrint('Stripe payment cancelled/failed: ${e.error.localizedMessage}');
      return false;
    } catch (e) {
      paymentErrorMessage = e.toString();
      debugPrint('General Payment Error: $e');
      return false;
    } finally {
      isProcessingPayment = false;
      notifyListeners();
    }
  }

  // =========================================================================
  // CANCELLATION BILLING
  // =========================================================================

  /// Returns the breakdown of actual fetched days and exact fees owed/refundable.
  /// Perfect for powering the cancellation confirmation screen UI.
  Future<Map<String, dynamic>?> getCancellationSummary(String subscriptionId) async {
    if (isOffline) {
      paymentErrorMessage = 'Cannot calculate exact cancellation fees while offline.';
      notifyListeners();
      return null;
    }

    try {
      return await _service.calculateCancellationFee(subscriptionId);
    } catch (e) {
      debugPrint('Error calculating cancellation summary: $e');
      return null;
    }
  }

  /// Executes the final bill generation upon successful cancellation.
  Future<bool> processCancellationBill(String subscriptionId) async {
    if (isOffline) {
      paymentErrorMessage = 'Cannot process cancellations while offline.';
      notifyListeners();
      return false;
    }

    isLoading = true;
    paymentErrorMessage = null;
    notifyListeners();

    try {
      await _service.generateCancellationInvoice(subscriptionId);
      await fetchAllPayments(); // Refresh list to instantly show the final bill
      return true;
    } catch (e) {
      paymentErrorMessage = 'Failed to generate final cancellation bill: $e';
      debugPrint(paymentErrorMessage);
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}