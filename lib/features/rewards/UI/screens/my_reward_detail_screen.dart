import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/rewards/UI/components/voucher_ticket.dart';

class MyRewardDetailScreen extends StatefulWidget {
  final Map<String, dynamic> userVoucher;

  const MyRewardDetailScreen({super.key, required this.userVoucher});

  @override
  State<MyRewardDetailScreen> createState() => _MyRewardDetailScreenState();
}

class _MyRewardDetailScreenState extends State<MyRewardDetailScreen> {
  bool showTnc = false;

  @override
  Widget build(BuildContext context) {
    final voucher = widget.userVoucher['vouchers'] ?? {};
    final code = widget.userVoucher['code'] ?? '';
    final expiredAt = DateTime.tryParse(widget.userVoucher['expired_at'] ?? '');
    final isUsed = widget.userVoucher['used_at'] != null;
    final isExpired = !isUsed && expiredAt != null && DateTime.now().isAfter(expiredAt);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        foregroundColor: AppColors.black,
        title: const Text('My Rewards', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            VoucherTicket(
              title: voucher['name'] ?? '',
              subtitle: isUsed ? 'Used' : (isExpired ? 'Expired' : 'Tap below to view your QR code'),
              captionText: 'Surprise for you!',
            ),
            const SizedBox(height: 16),
            Text(voucher['name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            if (expiredAt != null)
              Text('Valid until ${expiredAt.day}/${expiredAt.month}/${expiredAt.year}',
                  style: const TextStyle(color: AppColors.greyText)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => showTnc = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !showTnc ? AppColors.primaryYellow : AppColors.lightYellow,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Text('My Rewards', textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => showTnc = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: showTnc ? AppColors.primaryYellow : AppColors.lightYellow,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Text('Terms & Conditions', textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (!showTnc) ...[
              if (isUsed)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.inactiveRedBg, borderRadius: BorderRadius.circular(8)),
                  child: const Text('This voucher has already been used.',
                      style: TextStyle(color: AppColors.inactiveRedText, fontWeight: FontWeight.bold)),
                )
              else if (isExpired)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.inactiveRedBg, borderRadius: BorderRadius.circular(8)),
                  child: const Text('This voucher has expired and can no longer be used.',
                      style: TextStyle(color: AppColors.inactiveRedText, fontWeight: FontWeight.bold)),
                )
              else
                Image.asset('assets/qrcode.png', width: 220, height: 220),
              const SizedBox(height: 12),
              Text(code, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: Text(voucher['tnc'] ?? '', style: const TextStyle(color: AppColors.greyText, height: 1.6)),
              ),
          ],
        ),
      ),
    );
  }
}