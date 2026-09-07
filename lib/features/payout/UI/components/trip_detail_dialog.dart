import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payout/view_models/payout_view_model.dart';

// clicks on recent trips will show detailed receipt-like information
class TripDetailDialog extends StatelessWidget {
  final RecentTripDisplay trip;

  const TripDetailDialog({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: AppColors.primaryYellow),
                const SizedBox(width: 8),
                const Text('Trip receipt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Ref: ${_shortRef(trip.tripId)}',
              style: const TextStyle(color: AppColors.greyText, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _DetailRow(icon: Icons.person_outline, label: 'Passenger', value: trip.passengerName),
            const SizedBox(height: 12),
            _DetailRow(icon: Icons.trip_origin, label: 'Pickup', value: trip.pickupName),
            const SizedBox(height: 12),
            _DetailRow(icon: Icons.location_on_outlined, label: 'Drop-off', value: trip.dropoffName),
            const SizedBox(height: 12),
            _DetailRow(icon: Icons.calendar_today_outlined, label: 'Date', value: _formatDate(trip)),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.greyBorder),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(
                  child: Text('Earned', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(
                  '+${trip.points.toStringAsFixed(0)} pts',
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '≈ RM${trip.points.toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.greyText, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This trip has been added to your wallet balance. Use "Claim payout" '
                  'from the Wallet tab to withdraw it.',
              style: TextStyle(color: AppColors.greyText.withValues(alpha: 0.9), fontSize: 11.5),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(RecentTripDisplay trip) {
    final date = trip.tripDate;
    if (date == null) return trip.monthLabel;
    return '${date.day} ${trip.monthLabel} ${date.year}';
  }

  String _shortRef(String id) {
    if (id == '-') return '-';
    final cleaned = id.replaceAll('-', '');
    final ref = cleaned.length > 8 ? cleaned.substring(0, 8) : cleaned;
    return ref.toUpperCase();
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.greyText),
        const SizedBox(width: 10),
        Text('$label: ', style: const TextStyle(color: AppColors.greyText)),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}