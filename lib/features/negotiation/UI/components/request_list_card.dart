import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/negotiation_screen.dart';

class RequestListCard extends StatelessWidget {
  final TumpangRequest request;

  const RequestListCard({super.key, required this.request});

  String _formatAmPm(String dbTime) {
    if (dbTime.isEmpty) return dbTime;
    try {
      final parts = dbTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute $period';
    } catch (e) {
      return dbTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<NegotiationViewModel>();
    final isDriver = vm.currentUserRole == 'driver';
    final targetTripId = isDriver ? request.passengerTripId : request.driverTripId;

    // Determine status badge color and text
    Color badgeColor;
    Color textColor;
    String displayStatus;

    switch (request.status.toLowerCase()) {
      case 'completed':
        badgeColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        displayStatus = 'Completed';
        break;
      case 'cancelled':
        badgeColor = Colors.grey.shade200;
        textColor = Colors.grey.shade800;
        displayStatus = 'Cancelled';
        break;
      case 'rejected':
        badgeColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        displayStatus = 'Rejected';
        break;
      case 'negotiating':
        badgeColor = Colors.blue.shade50;
        textColor = Colors.blue.shade700;
        displayStatus = 'Negotiating';
        break;
      default:
        badgeColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        displayStatus = 'Pending';
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: vm.getUserProfileByTripId(targetTripId, isDriverTrip: !isDriver),
      builder: (context, snapshot) {
        final userData = snapshot.data;
        final displayName = userData?['name'] ?? userData?['full_name'] ?? 'Loading...';
        final phoneNumber = userData?['phone'] ?? userData?['phone_number'] ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.greyBorder, width: 1),
          ),
          elevation: 0,
          color: const Color(0xFFFFF8EE), // Card light warm background
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar box
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.greyBorder),
                      ),
                      child: const Icon(Icons.person, size: 32, color: Colors.grey),
                    ),
                    const SizedBox(width: 12),

                    // Request details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // User Name Title
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.black,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              displayStatus,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Route Direction
                          Text(
                            '${request.pickupLocation.name} - ${request.dropoffLocation.name}',
                            style: const TextStyle(fontSize: 13, color: AppColors.black),
                          ),
                          const SizedBox(height: 4),

                          // Pickup Time (Formatted AM/PM)
                          Text(
                            'pickup time: ${_formatAmPm(request.pickupTime.value)}',
                            style: const TextStyle(fontSize: 13, color: AppColors.black),
                          ),

                          // Phone Number
                          if (phoneNumber.toString().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              phoneNumber.toString(),
                              style: const TextStyle(fontSize: 13, color: AppColors.black),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Review Details Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryYellow,
                    foregroundColor: AppColors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NegotiationScreen(requestId: request.id),
                      ),
                    );
                  },
                  child: const Text('Review Details', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}