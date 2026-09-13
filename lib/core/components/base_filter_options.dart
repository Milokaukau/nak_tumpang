import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class BaseFilterOptions extends StatelessWidget {
  final List<String> options;
  final String selectedOption;
  final Function(String) onSelectionChanged;

  const BaseFilterOptions({
    super.key,
    required this.options,
    required this.selectedOption,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.map((option) {
        final isSelected = option == selectedOption;

        return Padding(
          padding: const EdgeInsets.only(right: 8.0), // Scaled down spacing between options
          child: GestureDetector(
            onTap: () => onSelectionChanged(option),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), // Scaled down inner padding
              decoration: BoxDecoration(
                border: isSelected ? null : Border.all(color: AppColors.greyBorder),
                borderRadius: BorderRadius.circular(6), // Slightly tighter radius
                color: isSelected ? AppColors.primaryYellow : AppColors.white,
              ),
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 13, // Scaled down font size
                  color: AppColors.black,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}