import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

class TripSelectionDropdown extends StatelessWidget {
  const TripSelectionDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();
    final trips = viewModel.availableTrips;
    final selectedId = viewModel.currentSelectedTrip?['id'];

    // Guard against a stale selection: if the previously selected trip is
    // no longer in `availableTrips` (e.g. it was just matched with a
    // driver and dropped from the list), passing that id as `value` has no
    // matching DropdownMenuItem and Flutter throws an assertion error.
    final hasMatchingItem = trips.any((trip) => trip['id'] == selectedId);
    final dropdownValue = hasMatchingItem ? selectedId : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.greyBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: dropdownValue,
          hint: const Text('Select a trip'),
          items: [
            const DropdownMenuItem(
              value: 'ADD_NEW',
              child: Text('+ Add New Trip', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryYellow)),
            ),
            ...trips.map((trip) {
              return DropdownMenuItem(
                value: trip['id'],
                child: Text(
                  trip['trip_name'] ?? 'Unnamed Trip',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
          onChanged: (value) {
            if (value == 'ADD_NEW') {
              // TODO: wire up navigation once the Add Trip screen exists.
              debugPrint('Navigate to Add Trip Screen');
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