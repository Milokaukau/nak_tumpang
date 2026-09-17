import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class NegotiationFieldRow extends StatelessWidget {
  final String title;
  final String value;
  final bool isAccepted;
  final bool isRequestedByMe;
  final bool isReadOnly;
  final bool isOffline;
  final VoidCallback onAccept;
  final VoidCallback onPropose;
  final Widget? topWidget;

  const NegotiationFieldRow({
    super.key,
    required this.title,
    required this.value,
    required this.isAccepted,
    required this.isRequestedByMe,
    required this.onAccept,
    required this.onPropose,
    this.isReadOnly = false,
    this.isOffline = false,
    this.topWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (isReadOnly) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10.0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.greyBorder),
        ),
        child: Column(
          children: [
            if (topWidget != null) ...[
              topWidget!,
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                      Text(value, style: const TextStyle(fontSize: 14, color: AppColors.black, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (isAccepted) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10.0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.greyBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                  Text(value, style: const TextStyle(fontSize: 14, color: AppColors.black, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            TextButton(
              onPressed: isOffline ? null : onPropose,
              child: const Text('Edit'),
            ),
          ],
        ),
      );
    }

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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (topWidget != null) ...[
                  topWidget!,
                  const SizedBox(height: 12),
                ] else ...[
                  _buildValueBox(value),
                  const SizedBox(height: 12),
                ],

                if (isRequestedByMe) ...[
                  const Text('(Waiting for Acceptance)', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.black,
                        side: const BorderSide(color: AppColors.greyBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      ),
                      onPressed: isOffline ? null : onPropose,
                      child: const Text('Edit'),
                    ),
                  ),
                ] else ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12.0),
                    child: Text('(Pending Your Review)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.black,
                            side: const BorderSide(color: AppColors.greyBorder),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                          ),
                          onPressed: isOffline ? null : onPropose,
                          child: const Text('Propose Another'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryYellow,
                            foregroundColor: AppColors.black,
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                          ),
                          onPressed: isOffline ? null : onAccept,
                          child: const Text('Accept'),
                        ),
                      ),
                    ],
                  ),
                ],
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
        color: AppColors.white,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, color: AppColors.black, fontWeight: FontWeight.w500),
      ),
    );
  }
}