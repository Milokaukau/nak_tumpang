import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/components/base_profile_card.dart';

class DirectRouteOptionCard extends StatelessWidget {
  final String driverName;
  final double distanceKm;
  final String departTime;
  final String? phoneNumber;
  final String? profileImageUrl;
  final bool isConfirmed;

  const DirectRouteOptionCard({
    super.key,
    required this.driverName,
    required this.distanceKm,
    required this.departTime,
    this.phoneNumber,
    this.profileImageUrl,
    this.isConfirmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return BaseProfileCard(
      hasBorder: false,
      padding: EdgeInsets.zero,
      profileImageUrl: profileImageUrl,

      // Title
      title: Text(
        driverName,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.black),
      ),

      // Description
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(Icons.directions_car, '${distanceKm.toStringAsFixed(1)} km from your pickup'),
          const SizedBox(height: 4),
          _buildInfoRow(Icons.access_time_filled, departTime),
          if (isConfirmed && phoneNumber != null) ...[
            const SizedBox(height: 4),
            _buildInfoRow(Icons.phone, phoneNumber!),
          ],
        ],
      ),

      // Action Buttons
      actionButtons: isConfirmed
          ? Column(
        children: [
          BaseButton(
            text: 'Call',
            onPressed: () => print('Calling $driverName...'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: AppColors.greyBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    foregroundColor: AppColors.black,
                  ),
                  child: const Text('Details'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: AppColors.greyBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    foregroundColor: AppColors.black,
                  ),
                  child: const Text('No need fetch'),
                ),
              ),
            ],
          ),
        ],
      )
          : BaseButton(
        text: 'Request tumpang',
        onPressed: () => print('Requesting tumpang with $driverName...'),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.primaryYellow),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: AppColors.black),
        ),
      ],
    );
  }
}