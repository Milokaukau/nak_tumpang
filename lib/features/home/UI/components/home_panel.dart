import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_filter_options.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/home/UI/components/direct_route_option_card.dart';
import 'package:nak_tumpang/features/home/UI/components/mixed_route_option_card.dart';
import 'package:nak_tumpang/features/home/UI/components/trip_selection_dropdown.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:nak_tumpang/features/home/UI/components/active_subscription_card.dart';
import 'package:nak_tumpang/features/trips/UI/add_edit_trip_screen.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/negotiation_screen.dart';
import 'package:nak_tumpang/core/utils/url_utils.dart';

class HomePanel extends StatelessWidget {
  const HomePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();

    return DraggableScrollableSheet(
      initialChildSize: viewModel.currentUserRole == 'driver' ? 0.5 : 0.6,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, spreadRadius: 1)],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 32,
            ),
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  height: 4,
                  width: 32,
                  decoration: BoxDecoration(
                    color: AppColors.greyBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (viewModel.isScreenLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primaryYellow)),
                )
              else if (viewModel.currentUserRole == 'driver')
                ..._buildDriverView(context, viewModel)
              else ...[
                  if (viewModel.activeSubscriptions.isNotEmpty && !viewModel.showMatchingUI)
                    ..._buildPassengerSubscriptionView(viewModel)
                  else
                    ..._buildPassengerMatchingView(context, viewModel),
                ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildDriverView(BuildContext context, HomeViewModel viewModel) {
    if (viewModel.activeSubscriptions.isNotEmpty) {
      return [
        const Text('My Active Subscriptions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ..._buildSubscriptionList(viewModel, isDriver: true),
      ];
    } else {
      return _buildDriverUnmatchedView(context, viewModel);
    }
  }

  List<Widget> _buildDriverUnmatchedView(BuildContext context, HomeViewModel viewModel) {
    if (viewModel.availableTrips.isEmpty) {
      return [_buildEmptyStatePrompt(context, viewModel)];
    }

    return [
      const TripSelectionDropdown(),
      const SizedBox(height: 24),
      if (NetworkService.isOfflineNotifier.value)
        const Center(
          child: Text(
            'Connect to the internet to find passengers.',
            style: TextStyle(color: AppColors.greyText, fontSize: 14),
          ),
        )
      else if (viewModel.currentSelectedTrip == null)
        _buildEmptyStatePrompt(context, viewModel)
      else
        const Center(
          child: Text(
            'Waiting for passenger requests...',
            style: TextStyle(color: AppColors.greyText, fontSize: 14),
          ),
        ),
    ];
  }

  List<Widget> _buildPassengerSubscriptionView(HomeViewModel viewModel) {
    return [
      const Text('My Active Subscriptions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      ..._buildSubscriptionList(viewModel, isDriver: false),
      const SizedBox(height: 16),
      const Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
      const SizedBox(height: 12),
      BaseButton(
        text: 'Find Tumpang for Another Trip',
        onPressed: () => viewModel.toggleMatchingUI(true),
        isOutlined: true,
        height: 40,
        borderColor: AppColors.greyBorder,
        textStyle: const TextStyle(color: AppColors.black, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    ];
  }

  List<Widget> _buildPassengerMatchingView(BuildContext context, HomeViewModel viewModel) {
    return [
      if (viewModel.activeSubscriptions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => viewModel.toggleMatchingUI(false),
              icon: const Icon(Icons.arrow_back, color: AppColors.black, size: 20),
              label: const Text('Back to Subscriptions', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ),
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

      // --- Offline check immediately replaces the results area ---
      if (NetworkService.isOfflineNotifier.value)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'Connect to the internet to find drivers.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.greyText, height: 1.4, fontSize: 14),
            ),
          ),
        )
      else if (viewModel.currentSelectedTrip == null)
        _buildEmptyStatePrompt(context, viewModel)
      else if (viewModel.selectedFilter == 'Direct') ...[
          // The spinner ONLY applies to the driver search results now
          if (viewModel.isDirectLoading)
            const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
          else if (viewModel.matchedDrivers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No direct drivers found for this route.\nTry selecting "Mixed".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.greyText, height: 1.4, fontSize: 13),
                ),
              ),
            )
          else ...[
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
                      isRequested: driver['is_requested'] ?? false,
                      onRequestTumpang: () async {
                        final requestId = await viewModel.requestTumpang(
                          driverTripId: driver['trip_id'],
                          passengerTripId: viewModel.currentSelectedTrip!['id'],
                        );
                        if (!context.mounted) return;
                        if (requestId != null) {
                          viewModel.markDriverRequestedGlobally([driver['trip_id']]);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request sent!'), backgroundColor: Colors.green));
                          Navigator.push(context, MaterialPageRoute(builder: (_) => NegotiationScreen(requestId: requestId)));
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send request.'), backgroundColor: Colors.red));
                        }
                      },
                    ),
                    if (index != viewModel.matchedDrivers.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
                      ),
                  ],
                );
              }),
              if (viewModel.isDirectLoadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primaryYellow)),
                )
              else if (viewModel.hasMoreDirect)
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: BaseButton(
                    text: 'Load More Options',
                    isOutlined: true,
                    height: 40,
                    foregroundColor: AppColors.black,
                    borderColor: AppColors.greyBorder,
                    onPressed: viewModel.loadMoreDirect,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
        ] else ...[
          // The spinner ONLY applies to the mixed search results now
          if (viewModel.isMixedLoading)
            const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
          else if (viewModel.mixedMatchedRoutes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No mixed routes available. Try selecting "Direct".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.greyText, height: 1.4, fontSize: 13),
                ),
              ),
            )
          else ...[
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
                      isRequested: route['is_requested'] ?? false,
                      onRequestTumpang: () async {
                        final selectedTrip = viewModel.currentSelectedTrip;
                        if (selectedTrip == null) return;

                        // A mixed route always has at least one driver leg
                        // (routes where both legs are Walk are filtered out
                        // in _findMixedRoutes), but never assume both legs
                        // exist -- request each independently, the same way
                        // the direct flow requests a single driver.
                        final driverATripId = route['driver_a_trip_id'] as String?;
                        final driverBTripId = route['driver_b_trip_id'] as String?;
                        final hasDriverA = route['first_mile_type'] == 'Driver' && driverATripId != null;
                        final hasDriverB = route['last_mile_type'] == 'Driver' && driverBTripId != null;

                        String? firstRequestId;
                        final requestedTripIds = <String>[];
                        var anyFailed = false;

                        if (hasDriverA) {
                          final requestId = await viewModel.requestTumpang(
                            driverTripId: driverATripId,
                            passengerTripId: selectedTrip['id'],
                            overridePickupLat: selectedTrip['pickup_lat'],
                            overridePickupLng: selectedTrip['pickup_lng'],
                            overridePickupName: selectedTrip['pickup_name'],
                            overrideDropoffLat: route['board_station_lat'],
                            overrideDropoffLng: route['board_station_lng'],
                            overrideDropoffName: route['board_station'],
                          );
                          if (requestId != null) {
                            requestedTripIds.add(driverATripId);
                            firstRequestId ??= requestId;
                          } else {
                            anyFailed = true;
                          }
                        }

                        if (hasDriverB) {
                          final requestId = await viewModel.requestTumpang(
                            driverTripId: driverBTripId,
                            passengerTripId: selectedTrip['id'],
                            overridePickupLat: route['alight_station_lat'],
                            overridePickupLng: route['alight_station_lng'],
                            overridePickupName: route['alight_station'],
                            overrideDropoffLat: selectedTrip['dropoff_lat'],
                            overrideDropoffLng: selectedTrip['dropoff_lng'],
                            overrideDropoffName: selectedTrip['dropoff_name'],
                          );
                          if (requestId != null) {
                            requestedTripIds.add(driverBTripId);
                            firstRequestId ??= requestId;
                          } else {
                            anyFailed = true;
                          }
                        }

                        if (!context.mounted) return;

                        if (requestedTripIds.isNotEmpty) {
                          viewModel.markDriverRequestedGlobally(requestedTripIds);
                        }

                        if (firstRequestId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to send request.'), backgroundColor: Colors.red),
                          );
                          return;
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              anyFailed
                                  ? 'Request sent for one leg -- the other driver could not be reached. Please retry.'
                                  : 'Request sent!',
                            ),
                            backgroundColor: anyFailed ? Colors.orange : Colors.green,
                          ),
                        );
                        Navigator.push(context, MaterialPageRoute(builder: (_) => NegotiationScreen(requestId: firstRequestId!)));
                      },
                    ),
                    if (index != viewModel.mixedMatchedRoutes.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
                      ),
                  ],
                );
              }),
              if (viewModel.isMixedLoadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primaryYellow)),
                )
              else if (viewModel.hasMoreMixed)
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: BaseButton(
                    text: 'Load More Options',
                    isOutlined: true,
                    height: 40,
                    foregroundColor: AppColors.black,
                    borderColor: AppColors.greyBorder,
                    onPressed: viewModel.loadMoreMixed,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
        ]
    ];
  }

  Widget _buildEmptyStatePrompt(BuildContext context, HomeViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            viewModel.availableTrips.isEmpty
                ? 'You have no trips to match.'
                : 'No trip is selected.\nSelect one from the dropdown, or',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.greyText, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddEditTripScreen()),
              );
            },
            child: const Text(
              'Add one now.',
              style: TextStyle(
                color: AppColors.primaryYellow,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primaryYellow,
                decorationThickness: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSubscriptionList(HomeViewModel viewModel, {required bool isDriver}) {
    return List.generate(viewModel.activeSubscriptions.length, (index) {
      final sub = viewModel.activeSubscriptions[index];
      return Column(
        children: [
          ActiveSubscriptionCard(
            tripName: sub['trip_name'],
            name: sub['name'],
            imageUrl: sub['imageUrl'],
            pickupLocation: sub['pickup_location'],
            dropoffLocation: sub['dropoff_location'],
            time: sub['pickup_time'],
            exceptionButtonText: isDriver ? "Can't fetch at..." : 'No need tumpang at...',
            isSelected: viewModel.selectedSubscriptionId == sub['id'],
            onTap: () => viewModel.selectSubscription(sub['id']),
            onCallPressed: () => UrlUtils.makePhoneCall(sub['phone']),
            onDetailsPressed: () => print('Opening details...'),
            onExceptionPressed: () => print('Filing exception...'),
          ),
          if (index != viewModel.activeSubscriptions.length - 1)
            const SizedBox(height: 12),
        ],
      );
    });
  }
}