import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payout/UI/components/payout_success_dialog.dart';
import 'package:nak_tumpang/features/payout/view_models/payout_view_model.dart';

/// "Claim payout" screen — amount (editable, capped at available
/// balance), method choice, and the bank/e-wallet fields for that
/// method. Confirm submits and shows PayoutSuccessDialog.
class PayoutMethodScreen extends StatelessWidget {
  const PayoutMethodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PayoutViewModel>();

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: const Text('Wallet')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.greyBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Available points', style: TextStyle(color: AppColors.greyText)),
                    const SizedBox(height: 4),
                    Text(
                      '${vm.availableBalance.toStringAsFixed(0)} pts',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '≈ RM${vm.availableBalance.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppColors.greyText),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text('Claim payout', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              const Text('Amount', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: vm.amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => vm.notifyUiOnly(),
                decoration: InputDecoration(
                  prefixText: 'RM ',
                  border: const OutlineInputBorder(),
                  errorText: vm.amountError,
                  helperText: 'Max: RM${vm.availableBalance.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(height: 20),
              const Text('Payout method', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _MethodTile(
                icon: Icons.account_balance,
                label: 'Bank transfer',
                subtitle: 'Transfer will be made within 3-5 working days.',
                selected: vm.selectedMethod == PayoutMethod.bankTransfer,
                onTap: () => vm.selectMethod(PayoutMethod.bankTransfer),
              ),
              const SizedBox(height: 8),
              _MethodTile(
                icon: Icons.account_balance_wallet,
                label: "Touch 'n Go eWallet",
                subtitle: 'Instant transfer to your eWallet.',
                selected: vm.selectedMethod == PayoutMethod.tngEwallet,
                onTap: () => vm.selectMethod(PayoutMethod.tngEwallet),
              ),
              const SizedBox(height: 16),
              if (vm.selectedMethod == PayoutMethod.bankTransfer) ...[
                TextField(
                  controller: vm.bankNameController,
                  decoration: InputDecoration(
                    labelText: 'Bank name',
                    border: const OutlineInputBorder(),
                    errorText: vm.bankNameError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: vm.bankAccNoController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Bank account number',
                    border: const OutlineInputBorder(),
                    errorText: vm.bankAccNoError,
                  ),
                ),
              ] else
                TextField(
                  controller: vm.ewalletPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: "Touch 'n Go eWallet phone number",
                    border: const OutlineInputBorder(),
                    errorText: vm.ewalletPhoneError,
                  ),
                ),
              const SizedBox(height: 24),
              if (vm.errorMessage != null) ...[
                Text(vm.errorMessage!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: BaseButton(
                      text: 'Cancel',
                      isOutlined: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BaseButton(
                      text: 'Confirm',
                      isLoading: vm.isSubmitting,
                      onPressed: () => _confirm(context, vm),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, PayoutViewModel vm) async {
    final amount = double.tryParse(vm.amountController.text.trim()) ?? 0;
    final success = await vm.submitPayout();
    if (!context.mounted) return;

    if (success) {
      await showDialog(
        context: context,
        builder: (_) => PayoutSuccessDialog(amount: amount),
      );
      if (context.mounted) {
        Navigator.pop(context); // back to the balance screen, now updated
      }
    }
    // On failure, vm.errorMessage / field errors are already set and
    // shown inline — nothing else to do here.
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _MethodTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.lightYellow : AppColors.white,
          border: Border.all(color: selected ? AppColors.primaryYellow : AppColors.greyBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? AppColors.primaryYellow : AppColors.greyText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(subtitle, style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
                ],
              ),
            ),
            Radio<bool>(
              value: true,
              groupValue: selected ? true : null,
              onChanged: (_) => onTap(),
              activeColor: AppColors.primaryYellow,
            ),
          ],
        ),
      ),
    );
  }
}
