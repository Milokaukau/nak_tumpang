import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

class TripSelectionDropdown extends StatelessWidget {
  const TripSelectionDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.greyBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: viewModel.currentPassengerTrip?['id'],
          items: [
            const DropdownMenuItem(
              value: 'ADD_NEW',
              child: Text('+ Add New Trip', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryYellow)),
            ),

            ...viewModel.availableTrips.map((trip) {
              return DropdownMenuItem(
                value: trip['id'],
                child: Text(trip['trip_name']),
              );
            }),
          ],
          onChanged: (value) {
            if (value == 'ADD_NEW') {
              print('Navigate to Add Trip Screen');
              // Navigator.pushNamed(context, '/add_trip');
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