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
    final netAmount = payoutNetAmount(widget.amount, vm.selectedMethod, vm.bankTransferFee);
    final isBank = vm.selectedMethod == PayoutMethod.bankTransfer;

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
              isBank
                  ? 'RM${netAmount.toStringAsFixed(2)} has been transferred to your bank account.\nYour points balance is now updated.'
                  : 'RM${widget.amount.toStringAsFixed(2)} is on its way to your Touch \'n Go '
                  'eWallet.\nYour points balance is now updated.',
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

class _PayoutStatusIndicator extends StatefulWidget {
  final String status;
  const _PayoutStatusIndicator({required this.status});

  @override
  State<_PayoutStatusIndicator> createState() => _PayoutStatusIndicatorState();
}

class _PayoutStatusIndicatorState extends State<_PayoutStatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // Loops only while status == 'pending' — that's now just the brief
    // moment before runPayoutStatusAnimation's mocked gateway resolves
    // to 'completed' (both payment methods), not an indefinite wait.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _PayoutStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _syncPulse();
  }

  void _syncPulse() {
    if (widget.status == 'pending') {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = payoutStatusColor(widget.status);
    final label = payoutStatusLabel(widget.status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.status == 'completed')
            Icon(Icons.check_circle, color: color, size: 14)
          else if (widget.status == 'processing')
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            FadeTransition(
              opacity: Tween(begin: 0.35, end: 1.0).animate(_pulseController),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
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