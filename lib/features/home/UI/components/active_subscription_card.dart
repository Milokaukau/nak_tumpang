import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_profile_card.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

class ActiveSubscriptionCard extends StatelessWidget {
  final String name;
  final String phone;
  final String? imageUrl;
  final String pickupLocation;
  final String dropoffLocation;
  final String time;
  final String exceptionButtonText;
  final bool isSelected;
  final VoidCallback? onTap;

  final VoidCallback onCallPressed;
  final VoidCallback onDetailsPressed;
  final VoidCallback onExceptionPressed;

  const ActiveSubscriptionCard({
    super.key,
    required this.name,
    required this.phone,
    this.imageUrl,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.time,
    required this.exceptionButtonText,
    this.isSelected = false,
    this.onTap,
    required this.onCallPressed,
    required this.onDetailsPressed,
    required this.onExceptionPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.primaryYellow : AppColors.greyBorder,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: BaseProfileCard(
            hasBorder: false,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            profileImageUrl: imageUrl,
            title: Text(
              name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            description: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: AppColors.primaryYellow),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        pickupLocation,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.keyboard_double_arrow_right, size: 16, color: AppColors.primaryYellow),
                    ),
                    const Icon(Icons.location_on_outlined, size: 16, color: AppColors.primaryYellow),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        dropoffLocation,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 16, color: AppColors.primaryYellow),
                    const SizedBox(width: 4),
                    Text(time, style: const TextStyle(fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 16, color: AppColors.primaryYellow),
                    const SizedBox(width: 4),
                    Text(phone, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ],
            ),
            actionButtons: Column(
              children: [
                BaseButton(
                  text: 'Call',
                  onPressed: onCallPressed,
                  height: 44,
                  foregroundColor: AppColors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: BaseButton(
                        text: 'Details',
                        onPressed: onDetailsPressed,
                        isOutlined: true,
                        height: 44,
                        textStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: BaseButton(
                        text: exceptionButtonText,
                        onPressed: onExceptionPressed,
                        isOutlined: true,
                        height: 44,
                        textStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}