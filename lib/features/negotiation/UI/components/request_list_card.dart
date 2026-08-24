import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/view_request_screen.dart';

class RequestListCard extends ConsumerWidget {
  final TumpangRequest request;

  const RequestListCard({
    super.key,
    required this.request,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(mockAuthUserProvider);
    final isDriver = currentUser.role == 'driver';
    final targetUserId = isDriver ? request.passengerId : request.driverId;
    final targetUserAsync = ref.watch(userProfileProvider(targetUserId));

    final displayName = targetUserAsync.maybeWhen(
      data: (userData) => userData?['name'] ?? userData?['full_name'] ?? targetUserId,
      orElse: () => 'Loading...',
    );

    final displayPhone = targetUserAsync.maybeWhen(
      data: (userData) => userData?['phone'] ?? userData?['phone_number'] ?? 'No phone provided',
      orElse: () => 'Loading...',
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // Centralized Border Color
        side: const BorderSide(color: AppColors.greyBorder, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.greyBorder, width: 1),
                  ),
                  child: const Icon(Icons.person, size: 40, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${request.pickupLocation.name} - ${request.dropoffLocation.name}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'pickup time: ${request.pickupTime.value}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayPhone,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Replaced with reusable BaseButton
            BaseButton(
              text: 'Review Details',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ViewRequestScreen(requestId: request.id),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}