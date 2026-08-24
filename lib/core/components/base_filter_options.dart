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
      // Maps through the provided options and builds a stylized button for each
      children: options.map((option) {
        final isSelected = option == selectedOption;

        return Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: GestureDetector(
            onTap: () => onSelectionChanged(option),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                border: isSelected ? null : Border.all(color: AppColors.greyBorder),
                borderRadius: BorderRadius.circular(8),
                color: isSelected ? AppColors.primaryYellow : AppColors.white,
              ),
              child: Text(
                option,
                style: TextStyle(
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