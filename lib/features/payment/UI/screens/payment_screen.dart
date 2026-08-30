import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/features/payment/view_models/payment_view_model.dart';
import 'package:nak_tumpang/features/payment/UI/components/tumpang_payment_card.dart';
import 'package:nak_tumpang/features/payment/UI/components/payment_bottom_bar.dart';
import 'package:nak_tumpang/features/payment/UI/components/payment_method_sheet.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PaymentViewModel>().fetchPayments();
    });
  }

  void _openPaymentSheet(BuildContext context, PaymentViewModel viewModel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => PaymentMethodSheet(
        amount: viewModel.totalSelectedAmount,
        onPaymentConfirmed: (methodDetails) async {
          final success = await viewModel.processMockPayment(methodDetails);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  success
                      ? 'Payment successful via $methodDetails!'
                      : 'Payment failed: ${viewModel.errorMessage}',
                ),
                backgroundColor: success ? Colors.green : Colors.red,
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Payments', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Consumer<PaymentViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (viewModel.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(viewModel.errorMessage!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => viewModel.fetchPayments(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (viewModel.pendingPayments.isEmpty) {
            return const Center(child: Text("All caught up! No pending payments."));
          }

          return ListView.builder(
            itemCount: viewModel.pendingPayments.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final payment = viewModel.pendingPayments[index];
              return TumpangPaymentCard(
                payment: payment,
                isSelected: viewModel.selectedPaymentIds.contains(payment.id),
                onChanged: (bool? value) {
                  viewModel.toggleSelection(payment.id);
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: Consumer<PaymentViewModel>(
        builder: (context, viewModel, child) {
          return PaymentBottomBar(
            totalAmount: viewModel.totalSelectedAmount,
            hasSelection: viewModel.selectedPaymentIds.isNotEmpty,
            onPayPressed: () => _openPaymentSheet(context, viewModel),
          );
        },
      ),
    );
  }
}