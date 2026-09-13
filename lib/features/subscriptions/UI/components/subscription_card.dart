import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

class SubscriptionCard extends StatelessWidget {
  final String tripName;
  final String name;
  final String phone;
  final String? imageUrl;
  final String pickupName;
  final String dropoffName;
  final String pickupTime;
  final bool isActive;
  final bool hasActiveException;
  final VoidCallback onViewDetails;
  final bool showPayButton;
  final VoidCallback? onPayPressed;

  const SubscriptionCard({
    super.key,
    required this.tripName,
    required this.name,
    required this.phone,
    this.imageUrl,
    required this.pickupName,
    required this.dropoffName,
    required this.pickupTime,
    required this.isActive,
    required this.hasActiveException,
    required this.onViewDetails,
    required this.showPayButton,
    required this.onPayPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tripName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.black),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Image placeholder
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                  image: imageUrl != null && imageUrl!.isNotEmpty
                      ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
                      : null,
                ),
                child: imageUrl == null || imageUrl!.isEmpty
                    ? const Icon(Icons.person, color: Colors.grey, size: 30)
                    : null,
              ),
              const SizedBox(width: 12),
              // Details Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.successGreenBg : AppColors.inactiveRedBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isActive ? 'ACTIVE' : 'INACTIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isActive ? AppColors.successGreenText : AppColors.inactiveRedText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.location_on, size: 14, color: AppColors.primaryYellow),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$pickupName >> $dropoffName',
                            style: const TextStyle(fontSize: 13, color: AppColors.black),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 14, color: AppColors.primaryYellow),
                        const SizedBox(width: 6),
                        Text(pickupTime, style: const TextStyle(fontSize: 13, color: AppColors.black)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 14, color: AppColors.primaryYellow),
                        const SizedBox(width: 6),
                        Text(phone, style: const TextStyle(fontSize: 13, color: AppColors.black)),
                      ],
                    ),
                    if (hasActiveException) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.notification_important, size: 14, color: AppColors.warningAmberText),
                          const SizedBox(width: 6),
                          const Text('Schedule change notified',
                              style: TextStyle(color: AppColors.warningAmberText, fontSize: 12)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: BaseButton(
              text: 'View Tumpang Details',
              onPressed: onViewDetails,
            ),
          ),
        ],
      ),
    );
  }
}