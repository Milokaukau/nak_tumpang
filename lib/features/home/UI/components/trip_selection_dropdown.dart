import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:nak_tumpang/features/trips/UI/add_edit_trip_screen.dart';

class TripSelectionDropdown extends StatelessWidget {
  const TripSelectionDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), // Scaled padding
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.greyBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          isDense: true, // Makes the dropdown more compact
          value: viewModel.currentSelectedTrip?['id'],
          hint: const Text('No trip selected', style: TextStyle(color: AppColors.greyText, fontSize: 13)), // Scaled font
          items: [
            const DropdownMenuItem(
              value: 'ADD_NEW',
              child: Text('+ Add New Trip', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryYellow, fontSize: 13)),
            ),
            ...viewModel.availableTrips.map((trip) {
              return DropdownMenuItem(
                value: trip['id'],
                child: Text(trip['trip_name'] ?? 'Unnamed Trip', style: const TextStyle(fontSize: 13)), // Scaled font
              );
            }),
          ],
          onChanged: (value) {
            if (value == 'ADD_NEW') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddEditTripScreen()),
              );
              return;
            }
            if (value != null) {
              viewModel.changeTrip(value);
            }
          },
        ),
      ),
    );
  }
}