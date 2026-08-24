import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

class NegotiationSummaryCard extends StatelessWidget {
  final TumpangRequest request;
  final VoidCallback onReject;
  final VoidCallback onAccept;

  const NegotiationSummaryCard({
    super.key,
    required this.request,
    required this.onReject,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
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
            decoration: const BoxDecoration(
              color: AppColors.primaryYellow,
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: const Text(
              'Negotiation Details',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.black),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryRow('Pickup Location', request.pickupLocation.name),
                _SummaryRow('Dropoff Location', request.dropoffLocation.name),
                _SummaryRow('Tumpang Start', request.subscriptionStartDate.value),
                _SummaryRow('Tumpang End', request.subscriptionEndDate.value),
                _SummaryRow('Pickup Time', request.pickupTime.value),
                const SizedBox(height: 12),
                _SummaryRow('Tumpang Fee', 'RM ${request.fee.value.toStringAsFixed(2)} (30 days)'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: AppColors.greyBorder),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: onReject,
                        child: const Text('Reject', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BaseButton(
                        text: 'Accept',
                        onPressed: onAccept,
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
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AppColors.black, fontSize: 14))),
          const Text(' : ', style: TextStyle(color: AppColors.black)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: AppColors.black))),
        ],
      ),
    );
  }
}