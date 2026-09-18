import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class BackToSubscriptionsButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const BackToSubscriptionsButton({
    super.key,
    required this.onPressed,
    this.label = 'Back to Subscriptions',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.arrow_back, color: AppColors.black, size: 20),
          label: Text(
            label,
            style: const TextStyle(color: AppColors.black, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ),
    );
  }
}