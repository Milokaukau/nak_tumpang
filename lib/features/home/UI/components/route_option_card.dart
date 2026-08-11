import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/components/base_button.dart';

class RouteOptionCard extends StatelessWidget {
  const RouteOptionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTimelineStep(
          location: 'house',
          isLast: false,
          child: _buildDriverInfo('Driver A', Icons.person),
        ),
        _buildTimelineStep(
          location: 'LRT KLCC',
          isLast: false,
          isDashed: true,
          child: _buildDriverInfo('LRT Kelana Jaya', Icons.train, isTransit: true),
        ),
        _buildTimelineStep(
          location: 'LRT Wangsa Maju',
          isLast: false,
          child: _buildDriverInfo('Driver B', Icons.person_4),
        ),
        _buildTimelineStep(
          location: 'TARUMT',
          isLast: true,
          child: const SizedBox(height: 4),
        ),

        const SizedBox(height: 16),
        BaseButton(
          text: 'Request tumpang',
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildTimelineStep({
    required String location,
    required bool isLast,
    required Widget child,
    bool isDashed = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left side: Circle and Line indicator
        Column(
          children: [
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 2), // Align circle with text
              decoration: const BoxDecoration(
                color: AppColors.lightYellow,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 70, // Fixed safe height for the line
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: isDashed ? Colors.transparent : AppColors.lightYellow,
                child: isDashed ? const _SafeDashedLine() : null,
              ),
          ],
        ),
        const SizedBox(width: 16),
        // Right side: Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                location,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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

  Widget _buildDriverInfo(String name, IconData icon, {bool isTransit = false}) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isTransit ? AppColors.transitRed : AppColors.driverBlueBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: isTransit ? AppColors.white : AppColors.greyText),
        ),
        const SizedBox(width: 12),
        Text(
          name,
          style: const TextStyle(fontSize: 14, color: AppColors.black),
        ),
      ],
    );
  }
}

// A crash-proof dashed line that doesn't rely on infinite LayoutBuilders
class _SafeDashedLine extends StatelessWidget {
  const _SafeDashedLine();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(
        8, // Number of dashes
            (index) => Container(
          width: 2,
          height: 4,
          color: AppColors.lightYellow,
        ),
      ),
    );
  }
}