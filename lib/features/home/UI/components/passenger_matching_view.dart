import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_filter_options.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/home/UI/components/back_to_subscriptions_button.dart';
import 'package:nak_tumpang/features/home/UI/components/direct_route_option_card.dart';
import 'package:nak_tumpang/features/home/UI/components/empty_state_message.dart';
import 'package:nak_tumpang/features/home/UI/components/mixed_route_option_card.dart';
import 'package:nak_tumpang/features/home/UI/components/trip_selection_dropdown.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

class PassengerMatchingView extends StatelessWidget {
  const PassengerMatchingView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();

    if (viewModel.availableTrips.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (viewModel.activeSubscriptions.isNotEmpty)
            BackToSubscriptionsButton(onPressed: () => viewModel.toggleMatchingUI(false)),
          const EmptyStateMessage(
            message: 'You have no pending trips to match.\nAll your trips currently have drivers!',
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (viewModel.activeSubscriptions.isNotEmpty)
          BackToSubscriptionsButton(onPressed: () => viewModel.toggleMatchingUI(false)),

        const TripSelectionDropdown(),
        const SizedBox(height: 16),
        const Text('Available options', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        BaseFilterOptions(
          options: const ['Direct', 'Mixed'],
          selectedOption: viewModel.selectedFilter,
          onSelectionChanged: (option) => viewModel.setFilter(option),
        ),
        const SizedBox(height: 16),

        if (NetworkService.isOfflineNotifier.value)
          const EmptyStateMessage(
            message: 'Connect to the internet to find drivers.',
            topSpacing: 24,
          )
        else if (viewModel.selectedFilter == 'Direct')
          _DirectResults(viewModel: viewModel)
        else
          _MixedResults(viewModel: viewModel),
      ],
    );
  }
}

class _DirectResults extends StatelessWidget {
  final HomeViewModel viewModel;
  const _DirectResults({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.isDirectLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow));
    }
    final drivers = viewModel.matchedDrivers;
    if (drivers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No direct drivers found for this route.\nTry selecting "Mixed".',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.greyText, height: 1.4, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < drivers.length; index++) ...[
          Builder(builder: (context) {
            final driver = drivers[index];
            final driverProfile = driver['driver_profile'] as Map<String, dynamic>?;
            return DirectRouteOptionCard(
              key: ValueKey(driver['id'] ?? index),
              driverName: driver['name'] ?? 'Unknown driver',
              phoneNumber: driver['phone'] ?? '',
              distanceKm: (driver['pickup_distance_km'] as num?)?.toDouble() ?? 0.0,
              departTime: driverProfile?['depart_time'] ?? '-',
              profileImageUrl: driver['profile_image_url'],
            );
          }),
          if (index != drivers.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
            ),
        ],
      ],
    );
  }
}

class _MixedResults extends StatelessWidget {
  final HomeViewModel viewModel;
  const _MixedResults({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.isMixedLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow));
    }
    final routes = viewModel.mixedMatchedRoutes;
    if (routes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No mixed routes available. Try selecting "Direct".',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.greyText, height: 1.4, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < routes.length; index++) ...[
          Builder(builder: (context) {
            final route = routes[index];
            return MixedRouteOptionCard(
              key: ValueKey(route['id'] ?? index),
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
              boardLineColor: route['board_line_color'] as Color? ?? AppColors.greyBorder,
              alightLineName: route['alight_line_name'],
              alightLineShortName: route['alight_line_short_name'],
              alightLineColor: route['alight_line_color'] as Color? ?? AppColors.greyBorder,
              trainDuration: route['train_duration_mins'],
              lastMileType: route['last_mile_type'],
              driverBName: route['driver_b_name'],
              driverBDepartTime: route['driver_b_depart'],
              dropoffDistanceKm: route['dropoff_distance_km'],
              walkToDestMeters: route['walk_to_dest_meters'],
              walkToDestMins: route['walk_to_dest_mins'],
            );
          }),
          if (index != routes.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
            ),
        ],
      ],
    );
  }
}