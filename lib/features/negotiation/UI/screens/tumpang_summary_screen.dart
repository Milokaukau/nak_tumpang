import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/summary_route_map.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:nak_tumpang/core/services/network_service.dart';

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

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
  }

  int _calculateDepositDays(int subscriptionDays) {
    if (subscriptionDays <= 0) return 0;
    return subscriptionDays <= 60 ? subscriptionDays : 60;
  }

  String _extractPaymentIntentId(String clientSecret) {
    final secretIndex = clientSecret.indexOf('_secret_');
    if (secretIndex == -1) {
      throw StateError('Unexpected PaymentIntent client secret format');
    }
    return clientSecret.substring(0, secretIndex);
  }

  Future<void> _handlePayDeposit({
    required TumpangRequest request,
    required double totalDeposit,
  }) async {
    setState(() => _isProcessing = true);

    try {
      final controller = context.read<NegotiationViewModel>();
      final clientSecret = await controller.createDepositPaymentIntent(
        amount: totalDeposit,
        requestId: request.id,
      );
      final paymentIntentId = _extractPaymentIntentId(clientSecret);

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Nak Tumpang',
          style: ThemeMode.light,
          billingDetails: const BillingDetails(
            address: Address(
              country: 'MY',
              city: null,
              line1: null,
              line2: null,
              postalCode: null,
              state: null,
            ),
          ),
        ),
      );

      await Stripe.instance.presentPaymentSheet();

      if (!mounted) return;

      if (request.isExtension) {
        await controller.finalizeExtensionRequest(
          extensionRequestId: request.id,
          additionalDeposit: totalDeposit,
          paymentIntentId: paymentIntentId,
        );
      } else {
        await controller.createSubscriptionAfterDeposit(
          request: request,
          deposit: totalDeposit,
          paymentIntentId: paymentIntentId,
        );
      }

      if (!mounted) return;

      try {
        await context.read<HomeViewModel>().fetchCurrentUser();
      } catch (e) {
        debugPrint('⚠️ Error refreshing HomeViewModel: $e');
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
          final schedule = snapshot.data!['schedule'] as Map<String, dynamic>?;
          if (schedule == null) {
            return const Center(child: Text('Error loading schedule details.'));
          }
          final dailyFee = request.fee.value;
          final depositDays = _calculateDepositDays(request.subscriptionDays);
          final startDate = DateTime.tryParse(request.subscriptionStartDate.value);
          final endDate = DateTime.tryParse(request.subscriptionEndDate.value);
          if (startDate == null || endDate == null) {
            return const Center(child: Text('Invalid subscription dates.'));
          }

          // FIX: DST-safe calendar math
          final potentialDepositEnd = DateTime(startDate.year, startDate.month, startDate.day + 59);
          final depositEndDate = potentialDepositEnd.isAfter(endDate) ? endDate : potentialDepositEnd;

          final depositActiveDays = NegotiationViewModel.countActiveDays(
            startDate,
            depositEndDate,
            schedule,
          );

          // FIX: Cleaned up vestigial oldDeposit math. Always charge the target total.
          final targetTotalDeposit = depositActiveDays * dailyFee;
          final payableDeposit = targetTotalDeposit;

          final totalActiveDays = NegotiationViewModel.countActiveDays(startDate, endDate, schedule);

          final invoicePeriods = NegotiationViewModel.calculateInvoicePeriods(
            startDate: startDate,
            endDate: endDate,
            dailyFee: dailyFee,
            schedule: schedule,
            depositDays: depositDays,
          );
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.black),
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
                        _SummaryRow(label: 'Tumpang Start', value: _formatDate(request.subscriptionStartDate.value)),
                        _SummaryRow(label: 'Tumpang End', value: _formatDate(request.subscriptionEndDate.value)),
                        _SummaryRow(label: 'Pickup Time', value: _formatAmPm(request.pickupTime.value)),
                        const SizedBox(height: 16),
                        _SummaryRow(
                          label: 'Tumpang Fee',
                          value: 'RM ${(dailyFee * totalActiveDays).toStringAsFixed(2)}',
                          isBold: true,
                        ),
                        const SizedBox(height: 8),

                        _SummaryRow(
                          label: request.isExtension ? 'Required Deposit' : 'Deposit',
                          value: 'RM ${payableDeposit.toStringAsFixed(2)}',
                          isBold: true,
                        ),

                        if (invoicePeriods.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _SummaryRow(
                            label: 'Remaining Balance',
                            value: 'RM ${remainingAmount.toStringAsFixed(2)}',
                            isBold: true,
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: NetworkService.isOfflineNotifier,
                            builder: (context, isOffline, _) => ElevatedButton(
                              style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryYellow,
                              foregroundColor: AppColors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            onPressed: _isProcessing || isOffline
                                ? null
                                : () => _handlePayDeposit(
                              request: request,
                              totalDeposit: payableDeposit,
                            ),
                            child: _isProcessing
                                ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black),
                            )
                                : Text(
                              'Pay RM ${payableDeposit.toStringAsFixed(2)} to confirm',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
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
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.black,
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(' : ', style: TextStyle(color: AppColors.black, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.black,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
