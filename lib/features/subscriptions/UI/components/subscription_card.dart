import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_profile_card.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

class SubscriptionCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final String pickupName;
  final String dropoffName;
  final String pickupTime;
  final bool isActive;
  final bool hasActiveException;
  final VoidCallback onViewDetails;

  const SubscriptionCard({
    super.key,
    required this.name,
    this.imageUrl,
    required this.pickupName,
    required this.dropoffName,
    required this.pickupTime,
    required this.isActive,
    required this.hasActiveException,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: BaseProfileCard(
        title: Row(
          children: [
            Flexible(
              child: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? AppColors.successGreenBg : AppColors.inactiveRedBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isActive ? 'ACTIVE' : 'INACTIVE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isActive ? AppColors.successGreenText : AppColors.inactiveRedText,
                ),
              ),
            ),
          ],
        ),
        description: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, size: 14, color: AppColors.primaryYellow),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('$pickupName - $dropoffName',
                      style: const TextStyle(color: AppColors.greyText),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: AppColors.primaryYellow),
                const SizedBox(width: 4),
                Text('pickup time: $pickupTime', style: const TextStyle(color: AppColors.greyText)),
              ],
            ),
            if (hasActiveException) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.notification_important, size: 14, color: AppColors.warningAmberText),
                  const SizedBox(width: 4),
                  const Text('Schedule change notified',
                      style: TextStyle(color: AppColors.warningAmberText, fontSize: 12)),
                ],
              ),
            ],
          ],
        ),
        actionButtons: BaseButton(text: 'View Tumpang Details', onPressed: onViewDetails),
      ),
    );
  }
}