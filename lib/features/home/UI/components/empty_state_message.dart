import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

/// Centered placeholder text used whenever a list (unmatched trips, pending
/// matches, etc.) has nothing to show. Extracted so every "empty" panel
/// looks and behaves the same way instead of re-declaring the same
/// Text/style pair in each build method.
class EmptyStateMessage extends StatelessWidget {
  final String message;
  final double topSpacing;

  const EmptyStateMessage({
    super.key,
    required this.message,
    this.topSpacing = 64,
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
            style: const TextStyle(color: AppColors.greyText, fontSize: 16, height: 1.5),
          ),
        ),
      ],
    );
  }
}