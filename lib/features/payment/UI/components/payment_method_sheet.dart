import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

enum PaymentMethodType { card, eWallet }

class PaymentMethodSheet extends StatefulWidget {
  final double amount;
  final Function(String methodDetails) onPaymentConfirmed;

  const PaymentMethodSheet({
    super.key,
    required this.amount,
    required this.onPaymentConfirmed,
  });

  @override
  State<PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<PaymentMethodSheet> {
  PaymentMethodType _selectedType = PaymentMethodType.card;

  // Hardcoded Mock Card Details for Emulator Testing
  final String _mockCardNumber = "4111 •••• •••• 4444";
  final String _mockCardExpiry = "12/28";

  // Hardcoded Mock e-Wallet Options
  String _selectedEWallet = "Touch 'n Go eWallet";
  final List<String> _eWalletOptions = [
    "Touch 'n Go eWallet",
    "GrabPay",
    "Boost",
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Select Payment Method',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),

          // Total Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryYellow.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Amount Due:', style: TextStyle(fontSize: 16)),
                Text(
                  'RM ${widget.amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Option 1: Mock Credit/Debit Card
          RadioListTile<PaymentMethodType>(
            value: PaymentMethodType.card,
            groupValue: _selectedType,
            activeColor: AppColors.primaryYellow,
            onChanged: (val) => setState(() => _selectedType = val!),
            title: const Text('Credit / Debit Card (Sandbox)'),
            subtitle: Text('Card: $_mockCardNumber (Exp: $_mockCardExpiry)'),
            secondary: const Icon(Icons.credit_card, color: Colors.blueAccent),
          ),

          // Option 2: Mock e-Wallet
          RadioListTile<PaymentMethodType>(
            value: PaymentMethodType.eWallet,
            groupValue: _selectedType,
            activeColor: AppColors.primaryYellow,
            onChanged: (val) => setState(() => _selectedType = val!),
            title: const Text('e-Wallet (Sandbox)'),
            subtitle: _selectedType == PaymentMethodType.eWallet
                ? DropdownButton<String>(
              value: _selectedEWallet,
              isExpanded: true,
              underline: const SizedBox(),
              items: _eWalletOptions.map((wallet) {
                return DropdownMenuItem(value: wallet, child: Text(wallet));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedEWallet = val);
              },
            )
                : Text(_selectedEWallet),
            secondary: const Icon(Icons.account_balance_wallet, color: Colors.green),
          ),

          const SizedBox(height: 20),

          // Confirm Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryYellow,
              foregroundColor: AppColors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(context);
              final details = _selectedType == PaymentMethodType.card
                  ? 'Card ($_mockCardNumber)'
                  : _selectedEWallet;
              widget.onPaymentConfirmed(details);
            },
            child: const Text('Confirm & Pay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}