import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

/// Left-aligned "back" text button used to return from the matching UI to
/// the active-subscriptions list. Shared by the driver and passenger panels
/// so the same widget isn't hand-copied in multiple places.
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.arrow_back, color: AppColors.black),
          label: Text(
            label,
            style: const TextStyle(color: AppColors.black, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}