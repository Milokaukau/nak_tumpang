import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class PointsSummaryCard extends StatelessWidget {
  final int availablePoints;
  final int usedPoints;
  final int voucherCount;
  final DateTime? nearestExpiry;

  const PointsSummaryCard({
    super.key,
    required this.availablePoints,
    required this.usedPoints,
    required this.voucherCount,
    this.nearestExpiry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('$availablePoints', 'Points Balance'),
              Container(width: 1, height: 40, color: AppColors.greyBorder),
              _stat('$usedPoints', 'Point Used'),
              Container(width: 1, height: 40, color: AppColors.greyBorder),
              _stat('$voucherCount', 'My Vouchers'),
            ],
          ),
          if (nearestExpiry != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryYellow,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                '$availablePoints points will expire by ${_formatDate(nearestExpiry!)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.black),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primaryYellow)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.greyText)),
      ],
    );
  }

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.year}';
  }
}