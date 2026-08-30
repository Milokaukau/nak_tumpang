import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_filter_options.dart';
import 'package:nak_tumpang/features/home/UI/components/direct_route_option_card.dart';
import 'package:nak_tumpang/features/home/UI/components/mixed_route_option_card.dart';
import 'package:nak_tumpang/features/home/UI/components/trip_selection_dropdown.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

class HomePanel extends StatelessWidget {
  const HomePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)],
          ),
          child: viewModel.isScreenLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
              : ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  height: 4, width: 40,
                  decoration: BoxDecoration(
                    color: AppColors.greyBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const TripSelectionDropdown(),
              const SizedBox(height: 24),

              const Text(
                'Available options',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              BaseFilterOptions(
                options: const ['Direct', 'Mixed'],
                selectedOption: viewModel.selectedFilter,
                onSelectionChanged: (option) => viewModel.setFilter(option),
              ),
              const SizedBox(height: 24),

              if (viewModel.selectedFilter == 'Direct') ...[
                if (viewModel.isDirectLoading)
                  const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
                else if (viewModel.matchedDrivers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No direct drivers found for this route.\nTry selecting "Mixed".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.greyText, height: 1.5),
                      ),
                    ),
                  )
                else
                  ...List.generate(viewModel.matchedDrivers.length, (index) {
                    final driver = viewModel.matchedDrivers[index];
                    final drivProfile = driver['driver_profile'];
                    return Column(
                      children: [
                        DirectRouteOptionCard(
                          driverName: driver['name'],
                          phoneNumber: driver['phone'],
                          distanceKm: driver['pickup_distance_km'] ?? 0.0,
                          departTime: drivProfile['depart_time'],
                          profileImageUrl: driver['profile_image_url'],
                        ),
                        if (index != viewModel.matchedDrivers.length - 1)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
                          ),
                      ],
                    );
                  }),
              ] else ...[
                if (viewModel.isMixedLoading)
                  const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
                else if (viewModel.mixedMatchedRoutes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No mixed routes available. Try selecting "Direct".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.greyText, height: 1.5),
                      ),
                    ),
                  )
                else
                  ...List.generate(viewModel.mixedMatchedRoutes.length, (index) {
                    final route = viewModel.mixedMatchedRoutes[index];

                    return Column(
                      children: [
                        MixedRouteOptionCard(
                          pickupLocation: route['pickup_name'],
                          destinationLocation: route['destination_name'],

                          firstMileType: route['first_mile_type'],
                          driverAName: route['driver_a_name'],
                          driverADepartTime: route['driver_a_depart'],
                          pickupDistanceKm: route['pickup_distance_km'],
                          walkToStationMeters: route['walk_to_station_meters'],
                          walkToStationMins: route['walk_to_station_mins'],

                          boardStation: route['board_station'],
                          alightStation: route['alight_station'],

                          isInterchange: route['is_interchange'],
                          boardLineName: route['board_line_name'],
                          boardLineShortName: route['board_line_short_name'],
                          boardLineColor: route['board_line_color'] as Color,
                          alightLineName: route['alight_line_name'],
                          alightLineShortName: route['alight_line_short_name'],
                          alightLineColor: route['alight_line_color'] as Color,
                          trainDuration: route['train_duration_mins'],

                          lastMileType: route['last_mile_type'],
                          driverBName: route['driver_b_name'],
                          driverBDepartTime: route['driver_b_depart'],
                          dropoffDistanceKm: route['dropoff_distance_km'],
                          walkToDestMeters: route['walk_to_dest_meters'],
                          walkToDestMins: route['walk_to_dest_mins'],
                        ),
                        if (index != viewModel.mixedMatchedRoutes.length - 1)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
                          ),
                      ],
                    );
                  }),
              ]
            ],
          ),
        );
      },
    );
  }
}