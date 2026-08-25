import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

class MixedRouteOptionCard extends StatelessWidget {
  // Empty constructor since we are keeping it hardcoded for now
  const MixedRouteOptionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step 1: Pickup & Driver Info
        _buildTimelineStep(
          location: 'PV13 Platinum Lake Condominium, Setapak',
          isLast: false,
          child: _buildDriverInfo('Ahmad Rayyan', Icons.person, '07:45 AM'),
        ),

        // Step 2: LRT Transfer Info
        _buildTimelineStep(
          location: 'Wangsa Maju LRT Station',
          isLast: false,
          child: _buildLrtInfo('Kelana Jaya Line', Icons.train, '10 mins to destination'),
        ),

        // Step 3: Final Dropoff
        _buildTimelineStep(
          location: 'TAR UMT Arena, Kuala Lumpur',
          isLast: true,
          child: const SizedBox(height: 4), // Empty space for the last node
        ),

        const SizedBox(height: 16),
        BaseButton(
          text: 'Request tumpang',
          onPressed: () {
            print('Requesting mixed route...');
          },
        ),
      ],
    );
  }

  Widget _buildTimelineStep({
    required String location,
    required bool isLast,
    required Widget child,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 2),
              decoration: const BoxDecoration(
                color: AppColors.lightYellow,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 70, // Fixed height for the connecting line
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: AppColors.lightYellow,
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                location,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              child,
              if (!isLast) const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDriverInfo(String name, IconData icon, String time) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.driverBlueBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.greyText),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontSize: 14, color: AppColors.black, fontWeight: FontWeight.w600),
            ),
            Text(
              'Departs at $time',
              style: const TextStyle(fontSize: 12, color: AppColors.greyText),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLrtInfo(String lineName, IconData icon, String duration) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.pink.shade50, // Distinct color for public transit
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.pink),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lineName,
              style: const TextStyle(fontSize: 14, color: AppColors.black, fontWeight: FontWeight.w600),
            ),
            Text(
              'Transit • $duration',
              style: const TextStyle(fontSize: 12, color: AppColors.greyText),
            ),
          ],
        ),
      ],
    );
  }
}