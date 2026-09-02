import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/payment.dart';
import 'package:nak_tumpang/features/payment/data/services/payment_supabase_service.dart';

class PaymentViewModel extends ChangeNotifier {
  final PaymentSupabaseService _service = PaymentSupabaseService();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Payment> pendingPayments = [];
  List<Payment> paymentHistory = [];
  Set<String> selectedPaymentIds = {};

  bool isLoading = false;
  bool isProcessingPayment = false;
  String? errorMessage;

  PaymentViewModel() {
    _initSession();
    _supabase.auth.onAuthStateChange.listen((data) {
      _initSession();
    });
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

      pendingPayments = await _service.fetchPendingPayments(userId);
      paymentHistory = await _service.fetchPaymentHistory(userId);
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
    if (selectedPaymentIds.isEmpty) return false;

    isProcessingPayment = true;
    notifyListeners();

    try {
      final secretKey = dotenv.env['STRIPE_SECRET_KEY'];
      if (secretKey == null || secretKey.isEmpty || !secretKey.startsWith('sk_')) {
        throw Exception('Invalid STRIPE_SECRET_KEY in .env file.');
      }

      final amountInCents = (totalSelectedAmount * 100).toInt();

      final response = await http.post(
        Uri.parse('https://api.stripe.com/v1/payment_intents'),
        headers: {
          'Authorization': 'Bearer $secretKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'amount': amountInCents.toString(),
          'currency': 'myr',
          'payment_method_types[]': 'card',
          'description': 'Nak Tumpang Invoice Settlement (${selectedPaymentIds.length} items)',
        },
      );

      if (response.statusCode != 200) {
        final err = jsonDecode(response.body);
        throw Exception(err['error']?['message'] ?? 'Stripe PaymentIntent failure.');
      }

      final paymentIntent = jsonDecode(response.body);

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntent['client_secret'],
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
      errorMessage = e.toString();
      debugPrint('General Payment Error: $e');
      return false;
    } finally {
      isProcessingPayment = false;
      notifyListeners();
    }
  }
}