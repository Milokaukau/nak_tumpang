import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payment/view_models/payment_view_model.dart';
import 'package:nak_tumpang/features/payment/UI/components/tumpang_payment_card.dart';
import 'package:nak_tumpang/features/payment/UI/components/payment_history_card.dart';
import 'package:nak_tumpang/features/payment/UI/components/payment_bottom_bar.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PaymentViewModel>().fetchAllPayments();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handlePayment(BuildContext context, PaymentViewModel viewModel) async {
    final success = await viewModel.paySelectedWithStripe();
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment Successful! Receipts updated.'),
          backgroundColor: Colors.green,
        ),
      );
      _tabController.animateTo(1);
    } else if (viewModel.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment Failed: ${viewModel.errorMessage}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Payments', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: AppColors.black),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.black,
          indicatorColor: AppColors.primaryYellow,
          indicatorWeight: 3.0,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Pending Payment'),
            Tab(text: 'Payment History'),
          ],
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

          return TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Pending Invoices
              RefreshIndicator(
                onRefresh: () => viewModel.fetchAllPayments(),
                child: viewModel.pendingPayments.isEmpty
                    ? Stack(
                  children: [
                    ListView(physics: const AlwaysScrollableScrollPhysics()),
                    const Center(child: Text('No pending invoices found.', style: TextStyle(fontSize: 15, color: Colors.grey))),
                  ],
                )
                    : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: viewModel.pendingPayments.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${viewModel.pendingPayments.length} pending bill${viewModel.pendingPayments.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            TextButton(
                              onPressed: () => viewModel.selectAll(),
                              child: Text(
                                viewModel.selectedPaymentIds.length == viewModel.pendingPayments.length
                                    ? 'Deselect All'
                                    : 'Select All',
                                style: const TextStyle(color: AppColors.black, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final payment = viewModel.pendingPayments[index - 1];
                    return TumpangPaymentCard(
                      key: ValueKey(payment.id),
                      payment: payment,
                      isSelected: viewModel.selectedPaymentIds.contains(payment.id),
                      onChanged: (bool? value) {
                        viewModel.toggleSelection(payment.id);
                      },
                    );
                  },
                ),
              ),

              // Tab 2: Payment History
              RefreshIndicator(
                onRefresh: () => viewModel.fetchAllPayments(),
                child: viewModel.paymentHistory.isEmpty
                    ? Stack(
                  children: [
                    ListView(physics: const AlwaysScrollableScrollPhysics()),
                    const Center(child: Text('No completed payments found.', style: TextStyle(fontSize: 15, color: Colors.grey))),
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
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Consumer<PaymentViewModel>(
        builder: (context, viewModel, child) {
          if (_tabController.index == 1 || viewModel.pendingPayments.isEmpty) {
            return const SizedBox.shrink();
          }
          return PaymentBottomBar(
            totalAmount: viewModel.totalSelectedAmount,
            selectedCount: viewModel.selectedPaymentIds.length,
            isProcessing: viewModel.isProcessingPayment,
            onPayPressed: () => _handlePayment(context, viewModel),
          );
        },
      ),
    );
  }
}