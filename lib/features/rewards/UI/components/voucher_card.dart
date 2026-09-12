import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'voucher_ticket.dart';

class VoucherCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? captionText;
  final VoidCallback onTap;
  final Widget? statusBadge;
  final bool isDisabled;

  const VoucherCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.captionText,
    required this.onTap,
    this.statusBadge,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDisabled ? 0.55 : 1.0,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.primaryYellow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              VoucherTicket(title: title, subtitle: subtitle, captionText: captionText),
              if (statusBadge != null) ...[
                const SizedBox(height: 12),
                statusBadge!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}