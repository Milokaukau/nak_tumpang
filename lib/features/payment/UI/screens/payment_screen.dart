// The main visual wrapper utilizing Consumer<PaymentViewModel>. It renders the ListView of cards and the dynamic "Pay Selected" bottom bar.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../view_models/payment_view_model.dart';
import '../components/tumpang_payment_card.dart';
import '../components/payment_bottom_bar.dart';

class PaymentScreen extends StatelessWidget {
  const PaymentScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Payments', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Consumer<PaymentViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.pendingPayments.isEmpty) {
            return const Center(child: Text("All caught up!"));
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
            onPayPressed: () {
              // Trigger your mock bank logic here
            },
          );
        },
      ),
    );
  }
}