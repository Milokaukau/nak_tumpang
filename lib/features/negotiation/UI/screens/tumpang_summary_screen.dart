import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/summary_route_map.dart';

class TumpangSummaryScreen extends StatefulWidget {
  final String requestId;

  const TumpangSummaryScreen({
    super.key,
    required this.requestId,
  });

  @override
  State<TumpangSummaryScreen> createState() => _TumpangSummaryScreenState();
}

class _TumpangSummaryScreenState extends State<TumpangSummaryScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isProcessing = false;

  int _calculateDepositMonths(DateTime start, DateTime? end) {
    if (end == null) return 3;
    final diffDays = end.difference(start).inDays;
    final months = (diffDays / 30).ceil();
    return months < 1 ? 1 : (months > 3 ? 3 : months);
  }

  Future<void> _handlePayDeposit(TumpangRequest request, double depositAmount) async {
    final controller = Provider.of<NegotiationViewModel>(context, listen: false);
    final passengerId = controller.currentUserId;

    setState(() => _isProcessing = true);

    try {
      // 1. Create a Payment Intent directly with Stripe
      final secretKey = dotenv.env['STRIPE_SECRET_KEY'];
      if (secretKey == null || secretKey.isEmpty) {
        throw Exception('STRIPE_SECRET_KEY is missing in .env');
      }

      final response = await http.post(
        Uri.parse('https://api.stripe.com/v1/payment_intents'),
        headers: {
          'Authorization': 'Bearer $secretKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'amount': (depositAmount * 100).toInt().toString(), // Amount in cents
          'currency': 'myr',
          'payment_method_types[]': 'card',
        },
      );

      if (response.statusCode != 200) {
        final err = jsonDecode(response.body);
        throw Exception(err['error']?['message'] ?? 'Failed to create PaymentIntent');
      }

      final paymentIntent = jsonDecode(response.body);
      final clientSecret = paymentIntent['client_secret'];

      // 2. Initialize the Native Stripe Payment Sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Nak Tumpang',
          style: ThemeMode.light,
        ),
      );

      // 3. Present the Sheet to User
      await Stripe.instance.presentPaymentSheet();

      // 4. Update Supabase Records on Success
      final startDate = DateTime.parse(request.subscriptionStartDate.value);
      final endDate = DateTime.tryParse(request.subscriptionEndDate.value);
      final subId = 'sub_${DateTime.now().millisecondsSinceEpoch}';

      await _supabase.from('tumpang_subscription').insert({
        'id': subId,
        'passenger_id': passengerId,
        'driver_id': request.pickupTime.requestedBy,
        'pickup_location': {
          'lat': request.pickupLocation.lat,
          'lng': request.pickupLocation.lng,
          'name': request.pickupLocation.name,
        },
        'dropoff_location': {
          'lat': request.dropoffLocation.lat,
          'lng': request.dropoffLocation.lng,
          'name': request.dropoffLocation.name,
        },
        'pickup_time': request.pickupTime.value,
        'fee': request.fee.value,
        'subscription_start_date': startDate.toIso8601String().split('T').first,
        'subscription_end_date': endDate?.toIso8601String().split('T').first,
        'deposit_amount': depositAmount,
        'deposit_status': 'held',
        'status': 'active',
      });

      final paymentId = 'pay_${DateTime.now().year.toString().substring(2)}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}_${subId.substring(4, 8)}';
      await _supabase.from('payments').insert({
        'id': paymentId,
        'tumpang_subscription_id': subId,
        'month': DateTime.now().month,
        'year': DateTime.now().year,
        'due_date': DateTime.now().toIso8601String(),
        'paid_at': DateTime.now().toIso8601String(),
      });

      await _supabase.from('tumpang_request').update({
        'status': 'completed',
      }).eq('id', request.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment Successful! Subscription is now active.'), backgroundColor: Colors.green),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);

    } on StripeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment Cancelled: ${e.error.localizedMessage ?? "User closed sheet"}'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<NegotiationViewModel>(context, listen: false);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: FutureBuilder<TumpangRequest?>(
        future: controller.getSingleRequest(widget.requestId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text('Error loading summary details.'));
          }

          final request = snapshot.data!;
          final monthlyFee = request.fee.value;
          final dailyFee = (monthlyFee / 30).toStringAsFixed(2);

          final startDate = DateTime.tryParse(request.subscriptionStartDate.value) ?? DateTime.now();
          final endDate = DateTime.tryParse(request.subscriptionEndDate.value);

          final depositMonths = _calculateDepositMonths(startDate, endDate);
          final depositAmount = depositMonths * monthlyFee;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.greyBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryYellow,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                    ),
                    child: const Text('Tumpang Summary', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.black)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: SizedBox(
                      height: 250,
                      child: SummaryRouteMap(
                        pickupLat: request.pickupLocation.lat,
                        pickupLng: request.pickupLocation.lng,
                        dropoffLat: request.dropoffLocation.lat,
                        dropoffLng: request.dropoffLocation.lng,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SummaryRow(label: 'Pickup Location', value: request.pickupLocation.name),
                        _SummaryRow(label: 'Dropoff Location', value: request.dropoffLocation.name),
                        _SummaryRow(label: 'Tumpang Start', value: request.subscriptionStartDate.value),
                        _SummaryRow(label: 'Tumpang End', value: request.subscriptionEndDate.value),
                        _SummaryRow(label: 'Pickup Time', value: request.pickupTime.value),
                        const SizedBox(height: 16),
                        _SummaryRow(label: 'Tumpang Fee', value: 'RM $dailyFee/day\nRM ${monthlyFee.toStringAsFixed(2)}/month', isBold: true),
                        const SizedBox(height: 8),
                        _SummaryRow(label: 'Deposit', value: 'RM ${depositAmount.toStringAsFixed(2)} ($depositMonths month${depositMonths > 1 ? 's' : ''})', isBold: true),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryYellow,
                              foregroundColor: AppColors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            onPressed: _isProcessing ? null : () => _handlePayDeposit(request, depositAmount),
                            child: _isProcessing
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black))
                                : const Text('pay deposit to confirm', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _SummaryRow({required this.label, required this.value, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: TextStyle(color: AppColors.black, fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
          Text(' : ', style: TextStyle(color: AppColors.black, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: AppColors.black, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
        ],
      ),
    );
  }
}