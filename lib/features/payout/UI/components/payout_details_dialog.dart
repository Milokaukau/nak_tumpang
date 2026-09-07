import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payout/UI/components/payout_success_dialog.dart';
import 'package:nak_tumpang/features/payout/data/constants/malaysian_banks.dart';
import 'package:nak_tumpang/features/payout/view_models/payout_view_model.dart';

// select payment method
// bring to payout success dialog
class PayoutDetailsDialog extends StatelessWidget {
  const PayoutDetailsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PayoutViewModel>();
    final isBank = vm.selectedMethod == PayoutMethod.bankTransfer;

    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isBank ? Icons.account_balance : Icons.account_balance_wallet,
                  color: AppColors.primaryYellow,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isBank ? 'Bank details' : "Touch 'n Go eWallet details",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'RM${(double.tryParse(vm.amountController.text.trim()) ?? 0).toStringAsFixed(2)} will be sent here once confirmed.',
              style: const TextStyle(color: AppColors.greyText, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (isBank) ...[
              DropdownButtonFormField<String>(
                initialValue: vm.selectedBankName,
                decoration: InputDecoration(
                  labelText: 'Bank name',
                  border: const OutlineInputBorder(),
                  errorText: vm.bankNameError,
                ),
                hint: const Text('Select your bank'),
                items: kMalaysianBanks
                    .map((bank) => DropdownMenuItem(value: bank, child: Text(bank)))
                    .toList(),
                onChanged: vm.selectBank,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: vm.bankAccNoController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(17),
                ],
                decoration: InputDecoration(
                  labelText: 'Bank account number',
                  border: const OutlineInputBorder(),
                  errorText: vm.bankAccNoError,
                ),
                onChanged: (_) {
                  if (vm.bankAccNoError != null) vm.clearBankAccNoError();
                },
              ),
            ] else
              _TngPhoneField(vm: vm),
            const SizedBox(height: 16),
            if (vm.errorMessage != null) ...[
              Text(vm.errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: BaseButton(
                    text: 'Back',
                    isOutlined: true,
                    onPressed: vm.isSubmitting ? () {} : () => Navigator.pop(context),
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
    );
  }

  Future<void> _confirm(BuildContext context, PayoutViewModel vm) async {
    final amount = double.tryParse(vm.amountController.text.trim()) ?? 0;
    final success = await vm.submitPayout();
    if (!context.mounted) return;

    if (success) {
      Navigator.pop(context); // close the details dialog
      await showDialog(
        context: context,
        // Re-wrap with the same vm — the Provider from ClaimPayoutDialog
        // only covers the details dialog's subtree, and that subtree is
        // gone once we pop above, so the success dialog needs its own.
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: PayoutSuccessDialog(amount: amount),
        ),
      );
    }
    // On failure, vm.errorMessage / field errors are already set and
    // shown inline in this dialog — nothing else to do here.
  }
}

/// Touch 'n Go phone entry, styled to match register_screen's phone
/// field: fixed '+60' prefix, digits-only input capped at 9 digits, and
/// a border that turns yellow on focus / red on error.
class _TngPhoneField extends StatelessWidget {
  final PayoutViewModel vm;
  const _TngPhoneField({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Phone Number", style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: vm.ewalletPhoneFocusNode,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: vm.ewalletPhoneError != null
                      ? Colors.red
                      : (vm.ewalletPhoneFocusNode.hasFocus
                      ? AppColors.primaryYellow
                      : AppColors.greyBorder),
                  width: (vm.ewalletPhoneError != null || vm.ewalletPhoneFocusNode.hasFocus)
                      ? 1.5
                      : 1,
                ),
              ),
              child: child,
            );
          },
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 14),
                child: Text(
                  '+60',
                  style: TextStyle(color: AppColors.greyText, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: vm.ewalletPhoneController,
                  focusNode: vm.ewalletPhoneFocusNode,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  style: const TextStyle(color: AppColors.black),
                  decoration: InputDecoration(
                    hintText: '123456789',
                    hintStyle: TextStyle(color: AppColors.greyText.withValues(alpha: 0.5)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (_) {
                    if (vm.ewalletPhoneError != null) vm.clearEwalletPhoneError();
                  },
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        if (vm.ewalletPhoneError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              vm.ewalletPhoneError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}