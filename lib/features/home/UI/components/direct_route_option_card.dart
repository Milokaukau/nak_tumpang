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
  final VoidCallback? onRequestTumpang;
  final bool isRequested;

  const DirectRouteOptionCard({
    super.key,
    required this.driverName,
    required this.distanceKm,
    required this.departTime,
    this.phoneNumber,
    this.profileImageUrl,
    this.isConfirmed = false,
    this.onRequestTumpang,
    this.isRequested = false,
  });

  @override
  Widget build(BuildContext context) {
    return BaseProfileCard(
      hasBorder: false,
      padding: EdgeInsets.zero,
      profileImageUrl: profileImageUrl,
      title: Text(
        driverName,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.black), // Scaled font
      ),
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(Icons.directions_car, '${distanceKm.toStringAsFixed(1)} km from your pickup'),
          const SizedBox(height: 2), // Tighter spacing
          _buildInfoRow(Icons.access_time_filled, departTime),
          if (isConfirmed && phoneNumber != null) ...[
            const SizedBox(height: 2),
            _buildInfoRow(Icons.phone, phoneNumber!),
          ],
        ],
      ),
      actionButtons: isConfirmed
          ? Column(
        children: [
          BaseButton(
            text: 'Call',
            onPressed: () => print('Calling $driverName...'),
            height: 36, // Scaled down height
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8), // Tighter vertical padding
                    side: const BorderSide(color: AppColors.greyBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    foregroundColor: AppColors.black,
                  ),
                  child: const Text('Details', style: TextStyle(fontSize: 12)), // Scaled font
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: AppColors.greyBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    foregroundColor: AppColors.black,
                  ),
                  child: const Text('No need fetch', style: TextStyle(fontSize: 12)), // Scaled font
                ),
              ),
            ],
          ),
        ],
      )
          : isRequested
          ? ElevatedButton(
        onPressed: () {}, // Disabled state
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey.shade200,
          foregroundColor: Colors.grey.shade500,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 10), // Scaled vertical padding
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 16), // Scaled icon
            SizedBox(width: 6),
            Text('Requested Tumpang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      )
          : BaseButton(
        text: 'Request tumpang',
        onPressed: onRequestTumpang,
        height: 40, // Scaled button height
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 12, color: AppColors.primaryYellow), // Scaled icon
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 11, color: AppColors.black), // Scaled font
        ),
      ],
    );
  }
}