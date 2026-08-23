import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
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
    // Read the current user to determine if we show the driver's or passenger's info
    final currentUser = ref.watch(mockAuthUserProvider);
    final isDriver = currentUser.role == 'driver';

    // The ID of the person we are negotiating with
    final targetUserId = isDriver ? request.passengerId : request.driverId;

    // Fetch their profile data from Firestore using the provider we created
    final targetUserAsync = ref.watch(userProfileProvider(targetUserId));

    // Gracefully handle loading states and extract the name
    final displayName = targetUserAsync.maybeWhen(
      data: (userData) => userData?['name'] ?? userData?['full_name'] ?? targetUserId,
      orElse: () => 'Loading...',
    );

    // Extract the phone number dynamically as well
    final displayPhone = targetUserAsync.maybeWhen(
      data: (userData) => userData?['phone'] ?? userData?['phone_number'] ?? 'No phone provided',
      orElse: () => 'Loading...',
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // TOP SECTION: Avatar and Text Details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar Placeholder
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                  ),
                  child: const Icon(Icons.person, size: 40, color: Colors.grey),
                ),
                const SizedBox(width: 16),

                // Text Information
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName, // NOW DISPLAYS THE ACTUAL NAME
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${request.pickupLocation.name} - ${request.dropoffLocation.name}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'pickup time: ${request.pickupTime.value}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayPhone, // NOW DISPLAYS THE ACTUAL PHONE NUMBER
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // BOTTOM SECTION: Full-width Action Button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB300),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Colors.black, width: 1.2),
                  ),
                ),
                onPressed: () {
                  // Push to the ViewRequestScreen properly so the button works
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ViewRequestScreen(requestId: request.id),
                    ),
                  );
                },
                child: const Text(
                  'Review Details',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}