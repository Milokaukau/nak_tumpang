import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class BaseProfileCard extends StatelessWidget {
  final String? profileImageUrl;
  final Widget title;
  final Widget description;
  final Widget? actionButtons;
  final bool hasBorder;
  final EdgeInsetsGeometry padding;

  const BaseProfileCard({
    super.key,
    this.profileImageUrl,
    required this.title,
    required this.description,
    this.actionButtons,
    this.hasBorder = true,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        border: hasBorder ? Border.all(color: AppColors.greyBorder) : null,
        borderRadius: BorderRadius.circular(12),
        color: AppColors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: profileImageUrl != null
                    ? Image.network(profileImageUrl!, width: 60, height: 60, fit: BoxFit.cover)
                    : Container(
                  width: 60,
                  height: 60,
                  color: AppColors.greyBorder,
                  child: const Icon(Icons.person, color: AppColors.greyText, size: 32),
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 4),
                    description,
                  ],
                ),
              ),
            ],
          ),

          if (actionButtons != null) ...[
            const SizedBox(height: 10),
            actionButtons!,
          ],
        ],
      ),
    );
  }
}