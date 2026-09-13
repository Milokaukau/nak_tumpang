import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class EmptyStateMessage extends StatelessWidget {
  final String message;
  final double topSpacing;

  const EmptyStateMessage({
    super.key,
    required this.message,
    this.topSpacing = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: topSpacing),
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.greyText, fontSize: 14, height: 1.4), // Scaled font
          ),
        ),
      ],
    );
  }
}