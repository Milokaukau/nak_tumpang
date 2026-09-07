import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payout/view_models/payout_view_model.dart';

// success dialog simulating a successful transaction
class PayoutSuccessDialog extends StatefulWidget {
  final double amount;

  const PayoutSuccessDialog({super.key, required this.amount});

  @override
  State<PayoutSuccessDialog> createState() => _PayoutSuccessDialogState();
}

class _PayoutSuccessDialogState extends State<PayoutSuccessDialog> {
  @override
  void initState() {
    super.initState();
    // Kick off the fake pending -> processing -> paid transition once
    // the dialog is actually on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PayoutViewModel>().runPayoutStatusAnimation();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PayoutViewModel>();

    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.green, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'Payout requested',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'RM${widget.amount.toStringAsFixed(2)} will be transferred to your account '
                  'within 3-5 working days.\nYour points balance is now updated.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.greyText),
            ),
            if (vm.lastPayoutId != null) ...[
              const SizedBox(height: 10),
              Text(
                'Transaction ID: ${vm.lastPayoutId}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.greyText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _PayoutStatusIndicator(status: vm.payoutStatus),
          ],
        ),
      ),
    );
  }
}

class _PayoutStatusIndicator extends StatelessWidget {
  final String status;
  const _PayoutStatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (status) {
      case 'paid':
        color = Colors.green;
        label = 'Paid';
        break;
      case 'processing':
        color = Colors.orange;
        label = 'Processing';
        break;
      default:
        color = AppColors.greyText;
        label = 'Pending';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'paid')
            Icon(Icons.check_circle, color: color, size: 14)
          else if (status == 'processing')
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}