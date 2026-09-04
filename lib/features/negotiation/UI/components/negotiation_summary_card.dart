import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

class NegotiationSummaryCard extends StatelessWidget {
  final TumpangRequest request;
  final bool isFullyAgreed;
  final bool isDriver;
  final bool isReadOnly;
  final VoidCallback onReject;
  final VoidCallback onProceedToSummary;

  // Lifecycle Callbacks
  final VoidCallback? onRenew;
  final VoidCallback? onRenegotiate;
  final VoidCallback? onCancelSubscription;

  const NegotiationSummaryCard({
    super.key,
    required this.request,
    required this.isFullyAgreed,
    required this.isDriver,
    this.isReadOnly = false,
    required this.onReject,
    required this.onProceedToSummary,
    this.onRenew,
    this.onRenegotiate,
    this.onCancelSubscription,
  });

  @override
  Widget build(BuildContext context) {
    final endDate = DateTime.tryParse(request.subscriptionEndDate.value) ?? DateTime.now();
    final now = DateTime.now();
    // Normalize to midnight for accurate day difference
    final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
    final nowOnly = DateTime(now.year, now.month, now.day);

    final isExpired = nowOnly.isAfter(endDateOnly);
    final daysUntilExpiry = endDateOnly.difference(nowOnly).inDays;
    final isExpiringSoon = daysUntilExpiry >= 0 && daysUntilExpiry <= 7;

    return Container(
      width: double.infinity,
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
            decoration: BoxDecoration(
              color: isReadOnly ? Colors.green.shade100 : AppColors.primaryYellow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Text(
              isReadOnly ? 'Agreement Finalized & Paid' : 'Agreement Status',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isReadOnly ? Colors.green.shade800 : AppColors.black,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isReadOnly) ...[
                  if (isExpired || isExpiringSoon) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Text(
                        isExpired
                            ? 'This subscription cycle ended on ${request.subscriptionEndDate.value}.'
                            : 'Subscription ends soon on ${request.subscriptionEndDate.value}.',
                        style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton.icon(
                      icon: const Icon(Icons.autorenew, color: AppColors.black),
                      label: const Text('Continue Subscription', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryYellow,
                        foregroundColor: AppColors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                        elevation: 0,
                      ),
                      onPressed: onRenew,
                    ),
                    const SizedBox(height: 10),

                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_note, color: AppColors.black),
                      label: const Text('Edit / Propose New Terms'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.black,
                        side: const BorderSide(color: AppColors.greyBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      ),
                      onPressed: onRenegotiate,
                    ),
                    const SizedBox(height: 6),

                    TextButton(
                      onPressed: onCancelSubscription,
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Cancel & Refund Deposit', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ] else ...[
                    const Row(
                      children: [
                        Icon(Icons.verified, color: Colors.green, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Payment complete. Route and terms are locked.',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ] else if (isFullyAgreed) ...[
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'All terms accepted by both parties.',
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!isDriver)
                    BaseButton(
                      text: 'View Tumpang Summary',
                      onPressed: onProceedToSummary,
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Waiting for the passenger to pay the deposit.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Please accept all terms above to proceed with the agreement.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (isDriver && !isReadOnly) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      ),
                      onPressed: onReject,
                      child: const Text('Reject Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}