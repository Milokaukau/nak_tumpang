import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

class NegotiationSummaryCard extends StatelessWidget {
  final TumpangRequest request;
  final bool isFullyAgreed;
  final bool isDriver;
  final bool isReadOnly;
  final bool isRejected;
  final bool isOffline;
  final VoidCallback onReject;
  final VoidCallback onCancelRequest;
  final VoidCallback onProceedToSummary;

  final VoidCallback? onRenew;
  final VoidCallback? onRenegotiate;
  final VoidCallback? onCancelSubscription;

  const NegotiationSummaryCard({
    super.key,
    required this.request,
    required this.isFullyAgreed,
    required this.isDriver,
    this.isReadOnly = false,
    this.isRejected = false,
    this.isOffline = false,
    required this.onReject,
    required this.onCancelRequest,
    required this.onProceedToSummary,
    this.onRenew,
    this.onRenegotiate,
    this.onCancelSubscription,
  });

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final endDate = DateTime.tryParse(request.subscriptionEndDate.value) ?? DateTime.now();
    final now = DateTime.now();
    final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
    final nowOnly = DateTime(now.year, now.month, now.day);

    final isExpired = nowOnly.isAfter(endDateOnly);
    final daysSinceExpiry = isExpired ? nowOnly.difference(endDateOnly).inDays : 0;
    final canStillExtend = isExpired && daysSinceExpiry < 7;

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
              color: isRejected
                  ? Colors.red.shade100
                  : (isReadOnly ? Colors.green.shade100 : AppColors.primaryYellow),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Text(
              isRejected
                  ? 'Request Rejected / Cancelled'
                  : (isReadOnly ? 'Agreement Finalized & Paid' : 'Agreement Status'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isRejected
                    ? Colors.red.shade800
                    : (isReadOnly ? Colors.green.shade800 : AppColors.black),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isRejected) ...[
                  const Row(
                    children: [
                      Icon(Icons.cancel, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This request was rejected or cancelled. No further changes can be made.',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ] else if (isReadOnly) ...[
                  if (canStillExtend) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Text(
                        'This subscription ended on ${_formatDate(request.subscriptionEndDate.value)}. '
                            'You can extend it within 7 days of ending (${7 - daysSinceExpiry} day${(7 - daysSinceExpiry) == 1 ? '' : 's'} left).',
                        style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (!isOffline) ...[
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
                    ]
                  ] else if (isExpired) ...[
                    const Row(
                      children: [
                        Icon(Icons.lock_clock, color: Colors.grey, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This subscription has ended and the 7-day extension window has passed.',
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
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

                  if (!isOffline) ...[
                    if (!isDriver)
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryYellow,
                                foregroundColor: AppColors.black,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: onProceedToSummary,
                              child: const Text('View Tumpang Summary', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.redAccent),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: onCancelRequest,
                              child: const Text('Cancel Request', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
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
                  ]
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

                if (!isReadOnly && !isRejected && !isOffline && !isFullyAgreed) ...[
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
                      onPressed: isDriver ? onReject : onCancelRequest,
                      child: Text(
                        isDriver ? 'Reject Request' : 'Cancel Request',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
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
