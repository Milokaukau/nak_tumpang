import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_profile_card.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

class ActiveSubscriptionCard extends StatelessWidget {
  final String tripName;
  final String name;
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
  final VoidCallback? onCompleteTripPressed;
  final bool isCompletedToday; // NEW: Controls the button state

  const ActiveSubscriptionCard({
    super.key,
    required this.tripName,
    required this.name,
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
    this.onCompleteTripPressed,
    this.isCompletedToday = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10), // Scaled radius
        border: Border.all(
          color: isSelected ? AppColors.primaryYellow : AppColors.greyBorder,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER: Extremely tight padding & small font ---
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 10, right: 10),
                child: Text(
                  tripName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.black),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.0),
                child: Divider(height: 12, thickness: 1, color: AppColors.greyBorder), // Scaled divider
              ),

              // --- BODY: Scaled down profile & details ---
              BaseProfileCard(
                hasBorder: false,
                padding: const EdgeInsets.only(left: 10, right: 10, bottom: 10),
                profileImageUrl: imageUrl,
                title: Text(
                  name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), // Scaled font
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                description: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 12, color: AppColors.primaryYellow), // Small icon
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            pickupLocation,
                            style: const TextStyle(fontSize: 11), // Small font
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.keyboard_double_arrow_right, size: 12, color: AppColors.primaryYellow),
                        ),
                        const Icon(Icons.location_on_outlined, size: 12, color: AppColors.primaryYellow),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            dropoffLocation,
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 12, color: AppColors.primaryYellow),
                        const SizedBox(width: 4),
                        Text(time, style: const TextStyle(fontSize: 11)), // Small font
                      ],
                    ),
                  ],
                ),

                // --- ACTION BUTTONS: Highly compressed buttons ---
                actionButtons: Column(
                  children: [
                    BaseButton(
                      text: 'Call',
                      onPressed: onCallPressed,
                      height: 32, // Minimum comfortable touch height
                      foregroundColor: AppColors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), // Scaled text
                    ),
                    const SizedBox(height: 6), // Very tight spacing
                    if (onCompleteTripPressed != null || isCompletedToday) ...[
                      const SizedBox(height: 10,),
                      BaseButton(
                        // Changes text dynamically
                        text: isCompletedToday ? 'Trip Today Completed' : 'Complete Trip Today',
                        // Null disables the button
                        onPressed: isCompletedToday ? null : onCompleteTripPressed,
                        isOutlined: true,
                        height: 44,
                        textStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: BaseButton(
                            text: 'Details',
                            onPressed: onDetailsPressed,
                            isOutlined: true,
                            height: 32,
                            textStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 11), // Scaled text
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 3,
                          child: BaseButton(
                            text: exceptionButtonText,
                            onPressed: onExceptionPressed,
                            isOutlined: true,
                            height: 32,
                            textStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 11), // Scaled text
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}