import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class FilterOptions extends StatelessWidget {
  const FilterOptions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Direct Button (Inactive)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.greyBorder),
            borderRadius: BorderRadius.circular(8),
            color: AppColors.white,
          ),
          child: const Text(
            'Direct',
            style: TextStyle(color: AppColors.black, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 12),
        // Mixed Button (Active)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppColors.primaryYellow,
          ),
          child: const Text(
            'Mixed',
            style: TextStyle(color: AppColors.black, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}