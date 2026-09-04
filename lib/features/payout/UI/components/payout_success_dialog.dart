import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

/// The "Payout requested" confirmation shown after a successful submit —
/// matches the third mockup screen. Shown with showDialog, not pushed as
/// a route, since it's an overlay on top of the method screen.
class PayoutSuccessDialog extends StatelessWidget {
  final double amount;

  const PayoutSuccessDialog({super.key, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.green, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'Payout requested',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'RM${amount.toStringAsFixed(2)} will be transferred to your account '
                  'within 3-5 working days.\nYour points balance is now updated.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.greyText),
            ),
          ],
        ),
      ),
    );
  }
}
