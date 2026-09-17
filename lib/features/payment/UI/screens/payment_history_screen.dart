import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/payment/view_models/payment_view_model.dart';
import 'package:nak_tumpang/features/payment/UI/components/payment_history_card.dart';

class PaymentHistoryScreen extends StatefulWidget {
  final String subscriptionId;

  const PaymentHistoryScreen({super.key, required this.subscriptionId});

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
    return ValueListenableBuilder<bool>(
      valueListenable: NetworkService.isOfflineNotifier,
      builder: (context, isOffline, _) {
        return Scaffold(
          backgroundColor: AppColors.white,
          appBar: AppBar(
            title: const Text('Payment History', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
            backgroundColor: AppColors.white,
            elevation: 0.5,
            iconTheme: const IconThemeData(color: AppColors.black),
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

              final subscriptionHistory = viewModel.paymentHistory
                  .where((p) => p.subscriptionId == widget.subscriptionId)
                  .toList();

              return RefreshIndicator(
                onRefresh: isOffline ? () async {} : () => viewModel.fetchAllPayments(),
                child: subscriptionHistory.isEmpty
                    ? Stack(
                  children: [
                    ListView(physics: const AlwaysScrollableScrollPhysics()),
                    const Center(
                      child: Text('No completed payments found.', style: TextStyle(fontSize: 15, color: Colors.grey)),
                    ),
                  ],
                )
                    : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: subscriptionHistory.length,
                  itemBuilder: (context, index) {
                    final payment = subscriptionHistory[index];
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
      },
    );
  }
}