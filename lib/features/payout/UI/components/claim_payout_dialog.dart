import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
                    '${pointsLabel(vm.availableBalance)} pts',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Amount', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _AmountField(vm: vm),
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
                  ? 'A RM${vm.bankTransferFee.toStringAsFixed(2)} processing fee applies.'
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

/// Amount entry, styled to match _TngPhoneField / the register screen's
/// phone field: a fixed 'RM' prefix that's always visible (not just on
/// focus, the way InputDecoration.prefixText behaves), a border that
/// turns yellow on focus / red on error, and a left-aligned error/helper
/// message under the box instead of InputDecoration's own error slot.
class _AmountField extends StatefulWidget {
  final PayoutViewModel vm;
  const _AmountField({required this.vm});

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  final _focusNode = FocusNode();

  static final _leadingZeroFormatter = TextInputFormatter.withFunction((oldValue, newValue) {
    var text = newValue.text.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (text.isEmpty) text = '0';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  });

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    // Selects the default '0' the moment the field gains focus, so the
    // first digit typed replaces it instead of appending after it
    // (e.g. typing '5' would otherwise leave '05').
    if (_focusNode.hasFocus && widget.vm.amountController.text == '0') {
      widget.vm.amountController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.vm.amountController.text.length,
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final hasError = vm.amountError != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: hasError
                  ? Colors.red
                  : (_focusNode.hasFocus ? AppColors.primaryYellow : AppColors.greyBorder),
              width: (hasError || _focusNode.hasFocus) ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 14),
                child: Text(
                  'RM',
                  style: TextStyle(color: AppColors.greyText, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: vm.amountController,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  // Blocks any non-digit keystroke (including '.') —
                  // matches the whole-number-only format
                  // PayoutViewModel.validateAmount enforces, so a driver
                  // can't even type something the validator will just
                  // reject a moment later.
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _leadingZeroFormatter,
                  ],
                  style: const TextStyle(color: AppColors.black),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (_) => vm.notifyUiOnly(),
                ),
              ),
              TextButton(
                onPressed: vm.setAmountToMax,
                child: const Text('Max'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            vm.amountError ?? 'Minimum RM${kMinPayoutAmount.toStringAsFixed(0)}',
            style: TextStyle(
              color: hasError ? Colors.red : AppColors.greyText,
              fontSize: 12,
            ),
          ),
        ),
      ],
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