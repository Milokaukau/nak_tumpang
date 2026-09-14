import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payout/view_models/payout_view_model.dart';

class PayoutHistoryDetailDialog extends StatelessWidget {
  final PayoutHistoryDisplay entry;

  const PayoutHistoryDetailDialog({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    entry.isEwallet ? Icons.account_balance_wallet : Icons.account_balance,
                    color: AppColors.primaryYellow,
                  ),
                  const SizedBox(width: 8),
                  const Text('Payout details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const Spacer(),
                  _StatusPill(status: entry.status),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(
                icon: Icons.monetization_on_outlined,
                label: 'Amount',
                value: 'RM${entry.amount.toStringAsFixed(2)}',
              ),
              if (entry.resolvedFee > 0) ...[
                const SizedBox(height: 12),
                _DetailRow(
                  icon: Icons.remove_circle_outline,
                  label: 'Processing fee',
                  value: '-RM${entry.resolvedFee.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  icon: Icons.check_circle_outline,
                  label: 'Net received',
                  value: 'RM${entry.netAmount.toStringAsFixed(2)}',
                ),
              ],
              const SizedBox(height: 12),
              _DetailRow(
                icon: entry.isEwallet ? Icons.account_balance_wallet_outlined : Icons.account_balance_outlined,
                label: 'Method',
                value: entry.isEwallet ? "Touch 'n Go eWallet" : 'Bank transfer',
              ),
              if (!entry.isEwallet) ...[
                const SizedBox(height: 12),
                _DetailRow(icon: Icons.account_balance_outlined, label: 'Bank', value: entry.bankName ?? '-'),
              ],
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.tag,
                label: entry.isEwallet ? 'Phone number' : 'Account number',
                value: entry.maskedDestination,
              ),
              const SizedBox(height: 12),
              _DetailRow(icon: Icons.calendar_today_outlined, label: 'Requested', value: _formatDate(entry.requestedAt)),
              const SizedBox(height: 12),
              _DetailRow(icon: Icons.receipt_long_outlined, label: 'Transaction ID', value: entry.id),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = payoutStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        payoutStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.greyText),
        const SizedBox(width: 10),
        Text('$label: ', style: const TextStyle(color: AppColors.greyText)),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}