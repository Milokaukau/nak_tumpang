import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/rewards/view_models/rewards_view_model.dart';
import 'package:nak_tumpang/features/rewards/UI/components/voucher_ticket.dart';

class VoucherDetailScreen extends StatelessWidget {
  final Map<String, dynamic> voucher;
  final String userId;
  final int availablePoints;

  const VoucherDetailScreen({
    super.key,
    required this.voucher,
    required this.userId,
    required this.availablePoints,
  });

  @override
  Widget build(BuildContext context) {
    final reqPoints = (voucher['req_points'] as num).toInt();
    final canRedeem = availablePoints >= reqPoints;
    final pointsNeeded = reqPoints - availablePoints;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        foregroundColor: AppColors.black,
        title: const Text('Voucher Details', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: VoucherTicket(
                    title: voucher['name'] ?? '',
                    subtitle: 'Redeem with $reqPoints points',
                    captionText: 'Point Voucher',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(voucher['name'] ?? '',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(voucher['description'] ?? '',
                          style: const TextStyle(color: AppColors.greyText)),
                      const SizedBox(height: 20),
                      _infoRow('Points', '$reqPoints Points'),
                      _infoRow('Validity', '${voucher['validity_days']} days'),
                      const SizedBox(height: 20),
                      const Text('Terms and Conditions:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(voucher['tnc'] ?? '', style: const TextStyle(color: AppColors.greyText, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${reqPoints}pts', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        canRedeem ? 'You have enough points' : 'Need $pointsNeeded more pts',
                        style: TextStyle(
                          fontSize: 12,
                          color: canRedeem ? AppColors.successGreenText : AppColors.warningAmberText,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: canRedeem
                        ? () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Redeem Voucher'),
                          content: Text('Redeem ${voucher['name']} for $reqPoints points?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Redeem')),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        final vm = context.read<RewardsViewModel>();
                        final success = await vm.redeemVoucher(userId, voucher);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(success ? 'Voucher redeemed!' : 'Redemption failed.')),
                          );
                          if (success) Navigator.of(context).pop();
                        }
                      }
                    }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryYellow,
                      disabledBackgroundColor: AppColors.greyBorder,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Text(canRedeem ? 'Redeem Now' : 'Not Enough Points',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(color: AppColors.greyText)),
        ],
      ),
    );
  }
}