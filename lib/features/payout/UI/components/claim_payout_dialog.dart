import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payout/UI/components/payout_details_dialog.dart';
import 'package:nak_tumpang/features/payout/view_models/payout_view_model.dart';

class ClaimPayoutDialog extends StatelessWidget {
  const ClaimPayoutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PayoutViewModel>();

    return Dialog(
      // Explicit white — Dialog's default background otherwise picks up
      // the app's yellow-seeded Material 3 surface tint instead of
      // staying plain white.
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Claim payout', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryYellow)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lightYellow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Text('Available points', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                  const Spacer(),
                  Text(
                    '${vm.availableBalance.toStringAsFixed(0)} pts',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
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
              ),
            ),
            const SizedBox(height: 20),
            const Text('Payout method', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _MethodTile(
              icon: Icons.account_balance,
              label: 'Bank transfer',
              selected: vm.selectedMethod == PayoutMethod.bankTransfer,
              onTap: () => vm.selectMethod(PayoutMethod.bankTransfer),
            ),
            const SizedBox(height: 8),
            _MethodTile(
              icon: Icons.account_balance_wallet,
              label: "Touch 'n Go eWallet",
              selected: vm.selectedMethod == PayoutMethod.tngEwallet,
              onTap: () => vm.selectMethod(PayoutMethod.tngEwallet),
            ),
            const SizedBox(height: 8),
            Text(
              vm.selectedMethod == PayoutMethod.bankTransfer
                  ? 'Transfer will be made within 3-5 working days.'
                  : 'Instant transfer to your eWallet.',
              style: const TextStyle(color: AppColors.greyText, fontSize: 12),
            ),
            const SizedBox(height: 20),
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

  void _confirm(BuildContext context, PayoutViewModel vm) {
    if (!vm.validateAmount()) return;

    Navigator.pop(context); // close this dialog
    showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: vm,
        child: const PayoutDetailsDialog(),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MethodTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.lightYellow : AppColors.white,
          border: Border.all(color: selected ? AppColors.primaryYellow : AppColors.greyBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? AppColors.primaryYellow : AppColors.greyText, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}