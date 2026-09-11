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

  int _calculateDepositDays(int subscriptionDays) {
    if (subscriptionDays <= 0) return 0;
    return subscriptionDays <= 60 ? subscriptionDays : 60;
  }

  Future<void> _handlePayDeposit({
    required TumpangRequest request,
    required double totalDeposit,
    required double additionalDeposit,
  }) async {
    setState(() => _isProcessing = true);

    try {
      // 1. If it's an extension and no new deposit is needed, skip Stripe entirely!
      if (request.isExtension && additionalDeposit <= 0) {
        await Provider.of<NegotiationViewModel>(context, listen: false)
            .finalizeExtensionRequest(
          extensionRequestId: request.id,
          additionalDeposit: 0.0,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Extension Finalized!'), backgroundColor: Colors.green),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

      // 2. Otherwise, charge the Required Amount via Stripe (either full or additional top-up)
      final chargeAmount = request.isExtension ? additionalDeposit : totalDeposit;

      final response = await _supabase.functions.invoke(
        'create-payment-intent',
        body: {
          'amount': chargeAmount,
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

      // 3. Backend Finalization
      if (request.isExtension) {
        // Route to the Extension logic
        await Provider.of<NegotiationViewModel>(context, listen: false)
            .finalizeExtensionRequest(
          extensionRequestId: request.id,
          additionalDeposit: additionalDeposit,
        );
      } else {
        // Standard Fresh Subscription Logic
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
          'deposit': totalDeposit,
          'deposit_refunded': false,
          'subscription_start_date': startDate.toIso8601String().split('T').first,
          'subscription_end_date': endDate.toIso8601String().split('T').first,
          'status': 'active',
        });

        final paidAt = DateTime.now();
        final paymentId = 'pay_${paidAt.millisecondsSinceEpoch}';

        await _supabase.from('payments').insert({
          'id': paymentId,
          'tumpang_subscription_id': subId,
          'month': paidAt.month,
          'year': paidAt.year,
          'due_date': paidAt.toIso8601String(),
          'paid_at': paidAt.toIso8601String(),
          'amount': totalDeposit,
        });

        await _supabase.from('tumpang_request').update({
          'status': 'completed',
        }).eq('id', request.id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment Successful!'), backgroundColor: Colors.green),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);

    } on StripeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment Cancelled: ${e.error.localizedMessage ?? "User closed sheet"}',
            style: const TextStyle(color: Colors.black),
          ),
          backgroundColor: Colors.red,
        ),
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
      body: FutureBuilder<Map<String, dynamic>?>(
        future: controller.getSummaryData(widget.requestId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text('Error loading summary details.'));
          }

          final request = snapshot.data!['request'] as TumpangRequest;
          final oldDeposit = snapshot.data!['oldDeposit'] as double;

          final dailyFee = request.fee.value;

          final depositDays = _calculateDepositDays(request.subscriptionDays);
          final targetTotalDeposit = depositDays * dailyFee;
          final bool depositCapped = request.subscriptionDays > 60;

          // Calculate "Top-Up" for extensions
          final additionalDeposit = request.isExtension
              ? (targetTotalDeposit - oldDeposit).clamp(0.0, double.infinity)
              : targetTotalDeposit;

          final invoicePeriods = NegotiationViewModel.calculateInvoicePeriods(
            subscriptionDays: request.subscriptionDays,
            dailyFee: dailyFee,
            depositDays: depositDays,
          );
          final int remainingDays = invoicePeriods.fold<int>(0, (sum, p) => sum + (p['days'] as int));
          final double remainingAmount = invoicePeriods.fold<double>(0, (sum, p) => sum + (p['amount'] as double));

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
                    child: Text(
                        request.isExtension ? 'Extension Summary' : 'Tumpang Summary',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.black)
                    ),
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
                        _SummaryRow(label: 'Pickup Time', value: _formatAmPm(request.pickupTime.value)),
                        const SizedBox(height: 16),
                        _SummaryRow(
                          label: 'Tumpang Fee',
                          value: 'RM ${dailyFee.toStringAsFixed(2)}/day\n'
                              'RM ${request.totalFee.toStringAsFixed(2)} for ${request.subscriptionDays} day${request.subscriptionDays == 1 ? '' : 's'}',
                          isBold: true,
                        ),
                        const SizedBox(height: 8),

                        // Render Deposit details dynamically based on if it's an extension
                        if (request.isExtension) ...[
                          _SummaryRow(
                            label: 'Total Required Deposit',
                            value: 'RM ${targetTotalDeposit.toStringAsFixed(2)} '
                                '($depositDays day${depositDays == 1 ? '' : 's'}'
                                '${depositCapped ? ' deposit, capped at 60 days' : ' deposit'})',
                          ),
                          _SummaryRow(
                            label: 'Prev. Paid Deposit',
                            value: 'RM ${oldDeposit.toStringAsFixed(2)}',
                          ),
                          _SummaryRow(
                            label: 'Additional Deposit',
                            value: 'RM ${additionalDeposit.toStringAsFixed(2)}',
                            isBold: true,
                          ),
                        ] else ...[
                          _SummaryRow(
                            label: 'Deposit',
                            value: 'RM ${targetTotalDeposit.toStringAsFixed(2)} '
                                '($depositDays day${depositDays == 1 ? '' : 's'}'
                                '${depositCapped ? ' deposit, capped at 60 days' : ' deposit'})',
                            isBold: true,
                          ),
                        ],

                        if (invoicePeriods.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _SummaryRow(
                            label: 'Remaining Balance',
                            value: 'RM ${remainingAmount.toStringAsFixed(2)} for $remainingDays day${remainingDays == 1 ? '' : 's'} total'
                                ' (billed as ${invoicePeriods.length} invoice${invoicePeriods.length == 1 ? '' : 's'} after the deposit period)\n'
                                '${invoicePeriods.map((p) => 'Day ${(p['startDay'] as int) + 1}\u2013${p['endDay']}: RM ${(p['amount'] as double).toStringAsFixed(2)} (${p['days']} day${p['days'] == 1 ? '' : 's'})').join('\n')}',
                            isBold: true,
                          ),
                        ],
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
                            onPressed: _isProcessing
                                ? null
                                : () => _handlePayDeposit(
                                request: request,
                                totalDeposit: targetTotalDeposit,
                                additionalDeposit: additionalDeposit
                            ),
                            child: _isProcessing
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black))
                                : Text(
                              request.isExtension && additionalDeposit <= 0
                                  ? 'Confirm Extension (No Deposit Required)'
                                  : 'Pay RM ${(request.isExtension ? additionalDeposit : targetTotalDeposit).toStringAsFixed(2)} to confirm',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
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