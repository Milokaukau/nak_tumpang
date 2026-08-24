import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class NegotiationFieldRow extends StatelessWidget {
  final String title;
  final String value;
  final bool isAccepted;
  final bool isRequestedByMe;
  final VoidCallback onAccept;
  final VoidCallback onPropose;
  final Widget? topWidget; // Used for passing the Map Placeholder

  const NegotiationFieldRow({
    super.key,
    required this.title,
    required this.value,
    required this.isAccepted,
    required this.isRequestedByMe,
    required this.onAccept,
    required this.onPropose,
    this.topWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Yellow Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.primaryYellow,
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.black),
            ),
          ),

          // Content Body
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (topWidget != null) ...[
                  topWidget!,
                  const SizedBox(height: 12),
                ],
                if (isAccepted)
                  _buildValueBox('✓ Accepted')
                else if (isRequestedByMe)
                  _buildValueBox('(Waiting for Acceptance)')
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.black,
                            side: const BorderSide(color: AppColors.greyBorder),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: onPropose,
                          child: const Text('Propose another'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.black,
                            side: const BorderSide(color: AppColors.greyBorder),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: onAccept,
                          child: const Text('Accept'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.greyBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, color: AppColors.black),
      ),
    );
  }
}