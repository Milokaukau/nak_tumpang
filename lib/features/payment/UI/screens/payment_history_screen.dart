import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payment/view_models/payment_view_model.dart';
import 'package:nak_tumpang/features/payment/UI/components/payment_history_card.dart';

/// Standalone screen listing a passenger's completed/paid invoices.
///
/// Previously this file accidentally duplicated the `PaymentHistoryCard`
/// widget class itself (same class name as
/// UI/components/payment_history_card.dart), which is a compile-time name
/// collision waiting to happen if both ever get imported into the same
/// file. This is now a real screen that reuses the actual card widget,
/// following the same fetch/loading/error/empty pattern used by
/// RequestListScreen and PaymentScreen.
class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PaymentViewModel>().fetchAllPayments();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Payment History', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: AppColors.black),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.black),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Consumer<PaymentViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (viewModel.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(viewModel.errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryYellow, foregroundColor: AppColors.black),
                      onPressed: () => viewModel.fetchAllPayments(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => viewModel.fetchAllPayments(),
            child: viewModel.paymentHistory.isEmpty
                ? Stack(
              children: [
                ListView(physics: const AlwaysScrollableScrollPhysics()),
                const Center(
                  child: Text(
                    'No completed payments found.\nPull down to refresh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: viewModel.paymentHistory.length,
              itemBuilder: (context, index) {
                final payment = viewModel.paymentHistory[index];
                return PaymentHistoryCard(
                  key: ValueKey(payment.id),
                  payment: payment,
                );
              },
            ),
          );
        },
      ),
    );
  }
}