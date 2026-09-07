import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class VoucherTicket extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? captionText;

  const VoucherTicket({
    super.key,
    required this.title,
    required this.subtitle,
    this.captionText,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.lightYellow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primaryYellow, width: 1.5),
          ),
          child: Column(
            children: [
              if (captionText != null) ...[
                Text(captionText!.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 11, letterSpacing: 1.5, color: AppColors.greyText, fontStyle: FontStyle.italic)),
                const SizedBox(height: 6),
              ],
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.black)),
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.greyText)),
            ],
          ),
        ),
        Positioned(
          left: -12,
          child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle)),
        ),
        Positioned(
          right: -12,
          child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle)),
        ),
      ],
    );
  }
}