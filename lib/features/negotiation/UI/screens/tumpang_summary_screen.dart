import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  String _formatAmPm(String dbTime) {
    if (dbTime.isEmpty) return dbTime;
    try {
      final parts = dbTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute $period';
    } catch (e) {
      return dbTime;
    }
  }

  /// Deposit rule:
  /// - subscription <= 60 days: deposit covers the FULL period (dailyFee * subscriptionDays)
  /// - subscription > 60 days: deposit is capped at 60 days' worth
  ///   (e.g. a 69-day subscription still only pays a 60-day deposit)
  double _calculateDeposit(double dailyFee, int subscriptionDays) {
    final depositDays = subscriptionDays > 60 ? 60 : subscriptionDays;
    return dailyFee * depositDays;
  }

  Future<void> _handlePayDeposit(TumpangRequest request, double depositAmount) async {
    setState(() => _isProcessing = true);

    try {
      final response = await _supabase.functions.invoke(
        'create-payment-intent',
        body: {
          'amount': depositAmount,
          'currency': 'myr',
          'description': 'Nak Tumpang deposit for request ${request.id}',
        },
      );

      if (response.status != 200 || response.data == null) {
        final err = response.data is Map ? response.data['error'] : null;
        throw Exception(err ?? 'Failed to create PaymentIntent');
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

      final startDate = DateTime.parse(request.subscriptionStartDate.value);
      final endDate = DateTime.tryParse(request.subscriptionEndDate.value) ?? startDate;
      final subId = 'sub_${DateTime.now().millisecondsSinceEpoch}';

      await _supabase.from('tumpang_subscription').insert({
        'id': subId,
        'passenger_trip_id': request.passengerTripId,
        'driver_trip_id': request.driverTripId,
        'pickup_lat': request.pickupLocation.lat,
        'pickup_lng': request.pickupLocation.lng,
        'pickup_location': request.pickupLocation.name,
        'dropoff_lat': request.dropoffLocation.lat,
        'dropoff_lng': request.dropoffLocation.lng,
        'dropoff_location': request.dropoffLocation.name,
        'pickup_time': request.pickupTime.value,
        'fee': request.fee.value,
        'deposit': depositAmount,
        'deposit_refunded': false,
        'subscription_start_date': startDate.toIso8601String().split('T').first,
        'subscription_end_date': endDate.toIso8601String().split('T').first,
        'status': 'active',
      });

      final paymentId = 'pay_${DateTime.now().millisecondsSinceEpoch}';
      await _supabase.from('payments').insert({
        'id': paymentId,
        'tumpang_subscription_id': subId,
        'month': DateTime.now().month,
        'year': DateTime.now().year,
        'due_date': DateTime.now().toIso8601String(),
        'paid_at': DateTime.now().toIso8601String(),
        'amount': depositAmount,
      });

      await _supabase.from('tumpang_request').update({
        'status': 'completed',
        'subscription_id': subId,
      }).eq('id', request.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment Successful!'), backgroundColor: Colors.green),
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
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
          final dailyFee = request.fee.value;

          final subscriptionDays = request.subscriptionDays;
          final depositDays = subscriptionDays > 60 ? 60 : subscriptionDays;
          final depositAmount = _calculateDeposit(dailyFee, subscriptionDays);

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
                        _SummaryRow(label: 'Pickup Time', value: _formatAmPm(request.pickupTime.value)), // ADDED FORMATTING HERE
                        const SizedBox(height: 16),
                        _SummaryRow(label: 'Tumpang Fee', value: 'RM ${dailyFee.toStringAsFixed(2)} / day\nTotal: RM ${request.totalFee.toStringAsFixed(2)} for $subscriptionDays day${subscriptionDays == 1 ? '' : 's'}', isBold: true),
                        const SizedBox(height: 8),
                        _SummaryRow(
                          label: 'Deposit',
                          value: subscriptionDays > 60
                              ? 'RM ${depositAmount.toStringAsFixed(2)} (fixed, capped at 60 days)'
                              : 'RM ${depositAmount.toStringAsFixed(2)} ($depositDays day${depositDays == 1 ? '' : 's'})',
                          isBold: true,
                        ),
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
                                : const Text('Pay deposit to confirm', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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