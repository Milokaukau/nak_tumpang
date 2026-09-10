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
  bool isProcessingPayment = false;
  String? errorMessage;
  String? paymentErrorMessage;

  bool get isOffline => NetworkService.isOfflineNotifier.value;

  PaymentViewModel() {
    _initSession();
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      _initSession();
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _initSession() {
    final session = _supabase.auth.currentSession;
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
        pendingPayments = await _service.fetchPendingPayments(userId);
        paymentHistory = await _service.fetchPaymentHistory(userId);

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
}