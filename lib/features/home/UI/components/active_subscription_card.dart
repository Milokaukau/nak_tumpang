import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_profile_card.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

class ActiveSubscriptionCard extends StatelessWidget {
  final String driverName;
  final String driverPhone;
  final String? driverImageUrl;
  final String pickupLocation;
  final String dropoffLocation;
  final String pickupTime;

  final VoidCallback onCallPressed;
  final VoidCallback onDetailsPressed;
  final VoidCallback onExceptionPressed;

  const ActiveSubscriptionCard({
    super.key,
    required this.driverName,
    required this.driverPhone,
    this.driverImageUrl,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.pickupTime,
    required this.onCallPressed,
    required this.onDetailsPressed,
    required this.onExceptionPressed,
  });

  @override
  Widget build(BuildContext context) {
    return BaseProfileCard(
      hasBorder: false,
      padding: const EdgeInsets.symmetric(vertical: 16),
      profileImageUrl: driverImageUrl,

      title: Text(
        driverName,
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
                  overflow: TextOverflow.ellipsis, // Prevents overflow
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
                  overflow: TextOverflow.ellipsis, // Prevents overflow
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: AppColors.primaryYellow),
              const SizedBox(width: 4),
              Text(pickupTime, style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.phone, size: 16, color: AppColors.primaryYellow),
              const SizedBox(width: 4),
              Text(driverPhone, style: const TextStyle(fontSize: 13)),
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
                flex: 2, // Takes up 40% of the available row space
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
                flex: 3, // Takes up 60% of the available row space
                child: BaseButton(
                  text: 'No need tumpang at...',
                  onPressed: onExceptionPressed,
                  isOutlined: true,
                  height: 44,
                  textStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13), // slightly smaller text to ensure safety on small screens
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}