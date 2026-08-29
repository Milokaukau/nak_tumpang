import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

class TripSelectionDropdown extends StatelessWidget {
  const TripSelectionDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();

    if (viewModel.availableTrips.isEmpty) {
      return const SizedBox.shrink(); // Hide if no trips exist
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Looking available drivers for:',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: viewModel.currentPassengerTrip?['id'],
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: Colors.amber, // Matches the yellow arrow in your UI
                size: 28,
              ),
              items: viewModel.availableTrips.map((trip) {
                return DropdownMenuItem<String>(
                  value: trip['id'],
                  child: Text(
                    trip['trip_name'] ?? 'Unnamed Trip',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (String? newTripId) {
                if (newTripId != null) {
                  viewModel.changeTrip(newTripId);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}