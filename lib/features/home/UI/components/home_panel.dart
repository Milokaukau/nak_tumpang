import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_filter_options.dart';
import 'package:nak_tumpang/features/home/UI/components/direct_route_option_card.dart';
import 'package:nak_tumpang/features/home/UI/components/mixed_route_option_card.dart';
import 'package:nak_tumpang/features/home/UI/components/trip_selection_dropdown.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:nak_tumpang/features/home/UI/components/active_subscription_card.dart';
import 'package:nak_tumpang/features/trips/UI/add_edit_trip_screen.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/negotiation_screen.dart';
import 'package:nak_tumpang/features/home/UI/components/cant_fetch_panel.dart';
import 'package:nak_tumpang/features/home/UI/components/no_need_fetch_panel.dart';
import 'package:nak_tumpang/features/subscriptions/UI/screens/subscription_detail_screen.dart';
import 'package:nak_tumpang/core/utils/url_utils.dart';

class HomePanel extends StatelessWidget {
  const HomePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();

    return DraggableScrollableSheet(
      initialChildSize: viewModel.currentUserRole == 'driver' ? 0.4 : 0.6,
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
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: AppColors.greyBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // --- PANEL MODE ROUTING (single source of truth — no duplicate block above this) ---
              if (viewModel.panelMode == HomePanelMode.cantFetch && viewModel.selectedSubscription != null)
                CantFetchPanel(
                  tumpangSubscriptionId: viewModel.selectedSubscription!['id'] ?? '',
                  driverId: viewModel.currentUserId ?? '',
                  passengerName: viewModel.selectedSubscription!['name'] ?? '',
                  passengerImageUrl: viewModel.selectedSubscription!['imageUrl'],
                  pickupName: viewModel.selectedSubscription!['pickup_location'] ?? '',
                  dropoffName: viewModel.selectedSubscription!['dropoff_location'] ?? '',
                  pickupTime: viewModel.selectedSubscription!['pickup_time'] ?? '',
                  passengerPhone: viewModel.selectedSubscription!['phone'] ?? '',
                  minDate: DateTime.tryParse(viewModel.selectedSubscription!['subscription_start_date'] ?? ''),
                  maxDate: DateTime.tryParse(viewModel.selectedSubscription!['subscription_end_date'] ?? ''),
                )
              else if (viewModel.panelMode == HomePanelMode.noNeedFetch && viewModel.selectedSubscription != null)
                NoNeedFetchPanel(
                  tumpangSubscriptionId: viewModel.selectedSubscription!['id'] ?? '',
                  passengerId: viewModel.currentUserId ?? '',
                  driverName: viewModel.selectedSubscription!['name'] ?? '',
                  driverImageUrl: viewModel.selectedSubscription!['imageUrl'],
                  pickupName: viewModel.selectedSubscription!['pickup_location'] ?? '',
                  dropoffName: viewModel.selectedSubscription!['dropoff_location'] ?? '',
                  pickupTime: viewModel.selectedSubscription!['pickup_time'] ?? '',
                  driverPhone: viewModel.selectedSubscription!['phone'] ?? '',
                  minDate: DateTime.tryParse(viewModel.selectedSubscription!['subscription_start_date'] ?? ''),
                  maxDate: DateTime.tryParse(viewModel.selectedSubscription!['subscription_end_date'] ?? ''),
                )
              else if (viewModel.currentUserRole == 'driver')
                  ..._buildDriverView(context, viewModel)
                else ...[
                    if (viewModel.activeSubscriptions.isNotEmpty && !viewModel.showMatchingUI)
                      ..._buildPassengerSubscriptionView(context, viewModel)
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
    if (viewModel.activeSubscriptions.isNotEmpty && !viewModel.showMatchingUI) {
      return [
        const Text('My Active Subscriptions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        // TODO: pass `context` + `isDriver: true` here once `active_subscription_card.dart`
        // is confirmed, so real onDetailsPressed / onExceptionPressed / Complete Trip
        // wiring can be restored (currently these are print() stubs in _buildSubscriptionList).
        ..._buildSubscriptionList(context, viewModel, isDriver: true),
        const SizedBox(height: 24),
        const Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
        const SizedBox(height: 16),
        BaseButton(
          text: 'View Unmatched Trips',
          onPressed: () => viewModel.toggleMatchingUI(true),
          isOutlined: true,
          height: 48,
          borderColor: AppColors.greyBorder,
          textStyle: const TextStyle(color: AppColors.black, fontWeight: FontWeight.bold),
        ),
      ];
    } else {
      return _buildDriverUnmatchedView(context, viewModel);
    }
  }

  List<Widget> _buildDriverUnmatchedView(BuildContext context, HomeViewModel viewModel) {
    // If they have no trips created yet at all
    if (viewModel.availableTrips.isEmpty && viewModel.activeSubscriptions.isEmpty) {
      return [_buildEmptyStatePrompt(context, viewModel)];
    }

    // --- FIX: Show text and hide dropdown if no subscriptions exist ---
    if (viewModel.activeSubscriptions.isEmpty) {
      return [
        const SizedBox(height: 32),
        const Center(
          child: Text(
            'No passenger to fetch today!',
            style: TextStyle(color: AppColors.greyText, fontSize: 16),
          ),
        ),
      ];
    }

    // Otherwise, they clicked "View Unmatched Trips" from the subscription list
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => viewModel.toggleMatchingUI(false),
            icon: const Icon(Icons.arrow_back, color: AppColors.black),
            label: const Text('Back to Subscriptions', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
      const TripSelectionDropdown(),
      const SizedBox(height: 32),
      if (viewModel.currentSelectedTrip == null)
        _buildEmptyStatePrompt(context, viewModel)
      else
        const Center(
          child: Text(
            'Waiting for passenger requests...',
            style: TextStyle(color: AppColors.greyText, fontSize: 16),
          ),
        ),
    ];
  }

  List<Widget> _buildPassengerSubscriptionView(BuildContext context, HomeViewModel viewModel) {
    return [
      const Text('My Active Subscriptions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      // Use the unified list builder with context
      ..._buildSubscriptionList(context, viewModel, isDriver: false),
      const SizedBox(height: 24),
      const Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
      const SizedBox(height: 16),
      BaseButton(
        text: 'Find Tumpang for Another Trip',
        onPressed: () => viewModel.toggleMatchingUI(true),
        isOutlined: true,
        height: 48,
        borderColor: AppColors.greyBorder,
        textStyle: const TextStyle(color: AppColors.black, fontWeight: FontWeight.bold),
      ),
    ];
  }
  List<Widget> _buildPassengerMatchingView(BuildContext context, HomeViewModel viewModel) {
    return [
      if (viewModel.activeSubscriptions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => viewModel.toggleMatchingUI(false),
              icon: const Icon(Icons.arrow_back, color: AppColors.black),
              label: const Text('Back to Subscriptions', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      const TripSelectionDropdown(),
      const SizedBox(height: 24),
      const Text('Available options', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      BaseFilterOptions(
        options: const ['Direct', 'Mixed'],
        selectedOption: viewModel.selectedFilter,
        onSelectionChanged: (option) => viewModel.setFilter(option),
      ),
      const SizedBox(height: 24),

      if (viewModel.currentSelectedTrip == null)
        _buildEmptyStatePrompt(context, viewModel)
      else if (viewModel.selectedFilter == 'Direct') ...[
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Request sent!'), backgroundColor: Colors.green),
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => NegotiationScreen(requestId: requestId)),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to send request.'), backgroundColor: Colors.red),
                        );
                      }
                    },
                  ),
                  if (index != viewModel.matchedDrivers.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
                    ),
                ],
              );
            }),
            if (viewModel.isDirectLoadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: AppColors.primaryYellow)),
              )
            else if (viewModel.hasMoreDirect)
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: BaseButton(
                  text: 'Load More Options',
                  isOutlined: true,
                  height: 48,
                  foregroundColor: AppColors.black,
                  borderColor: AppColors.greyBorder,
                  onPressed: viewModel.loadMoreDirect,
                ),
              ),
          ],
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
                      String? requestIdA;
                      String? requestIdB;
                      final bool attemptA = route['first_mile_type'] == 'Driver' &&
                          route['driver_a_trip_id'] != null &&
                          !(route['is_driver_a_requested'] ?? false);
                      final bool attemptB = route['last_mile_type'] == 'Driver' &&
                          route['driver_b_trip_id'] != null &&
                          !(route['is_driver_b_requested'] ?? false);
                      if (attemptA) {
                        requestIdA = await viewModel.requestTumpang(
                          driverTripId: route['driver_a_trip_id'],
                          passengerTripId: viewModel.currentSelectedTrip!['id'],
                          overridePickupLat: viewModel.currentSelectedTrip!['pickup_lat'],
                          overridePickupLng: viewModel.currentSelectedTrip!['pickup_lng'],
                          overridePickupName: viewModel.currentSelectedTrip!['pickup_name'],
                          overrideDropoffLat: route['board_station_lat'],
                          overrideDropoffLng: route['board_station_lng'],
                          overrideDropoffName: route['board_station'],
                          overridePickupTime: viewModel.currentSelectedTrip!['desired_pickup_time'],
                        );
                      }

                      if (attemptB) {
                        requestIdB = await viewModel.requestTumpang(
                          driverTripId: route['driver_b_trip_id'],
                          passengerTripId: viewModel.currentSelectedTrip!['id'],
                          overridePickupLat: route['alight_station_lat'],
                          overridePickupLng: route['alight_station_lng'],
                          overridePickupName: route['alight_station'],
                          overrideDropoffLat: viewModel.currentSelectedTrip!['dropoff_lat'],
                          overrideDropoffLng: viewModel.currentSelectedTrip!['dropoff_lng'],
                          overrideDropoffName: viewModel.currentSelectedTrip!['dropoff_name'],
                          overridePickupTime: route['driver_b_depart_sql'],
                        );
                      }

                      if (!context.mounted) return;

                      final bool successA = attemptA ? (requestIdA != null) : true;
                      final bool successB = attemptB ? (requestIdB != null) : true;
                      final bool allSuccess = successA && successB;

                      if (allSuccess) {
                        List<String> requestedIds = [];
                        if (requestIdA != null) requestedIds.add(route['driver_a_trip_id']);
                        if (requestIdB != null) requestedIds.add(route['driver_b_trip_id']);

                        if (requestedIds.isNotEmpty) {
                          viewModel.markDriverRequestedGlobally(requestedIds);
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Mixed requests sent successfully!'), backgroundColor: Colors.green),
                        );

                        final targetId = requestIdA ?? requestIdB;
                        if (targetId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => NegotiationScreen(requestId: targetId)),
                          );
                        }
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to send one or more requests.'), backgroundColor: Colors.red),
                        );
                      }
                    },
                  ),
                  if (index != viewModel.mixedMatchedRoutes.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
                    ),
                ],
              );
            }),

            // --- UPDATED: Show mini spinner below the list during pagination ---
            if (viewModel.isMixedLoadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: AppColors.primaryYellow)),
              )
            else if (viewModel.hasMoreMixed)
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: BaseButton(
                  text: 'Load More Options',
                  isOutlined: true,
                  height: 48,
                  foregroundColor: AppColors.black,
                  borderColor: AppColors.greyBorder,
                  onPressed: viewModel.loadMoreMixed,
                ),
              ),
          ],
      ]
    ];
  }

  Widget _buildEmptyStatePrompt(BuildContext context, HomeViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Text(
            viewModel.availableTrips.isEmpty
                ? 'You have no trips to match.'
                : 'No trip is selected.\nSelect one from the dropdown, or',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.greyText, fontSize: 16, height: 1.5),
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
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primaryYellow,
                decorationThickness: 2.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // UNCHANGED FROM MERGE — still has print() stubs, needs active_subscription_card.dart
  // to restore real navigation + add Complete Trip. See TODOs above.
  List<Widget> _buildSubscriptionList(BuildContext context, HomeViewModel viewModel, {required bool isDriver}) {
    return List.generate(viewModel.activeSubscriptions.length, (index) {
      final sub = viewModel.activeSubscriptions[index];
      final bool isCompletedToday = sub['is_completed_today'] ?? false;

      return Column(
        children: [
          ActiveSubscriptionCard(
            tripName: sub['trip_name'],
            name: sub['name'],
            phone: sub['phone'],
            imageUrl: sub['imageUrl'],
            pickupLocation: sub['pickup_location'],
            dropoffLocation: sub['dropoff_location'],
            time: sub['pickup_time'],
            exceptionButtonText: isDriver ? "Can't fetch at..." : 'No need tumpang at...',
            isSelected: viewModel.selectedSubscriptionId == sub['id'],
            onTap: () => viewModel.selectSubscription(sub['id']),
            // Trigger the native dialer
            onCallPressed: () => UrlUtils.makePhoneCall(sub['phone']),
            onDetailsPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubscriptionDetailScreen(
                    currentUserId: viewModel.currentUserId ?? '',
                    role: viewModel.currentUserRole,
                    subscription: sub,
                  ),
                ),
              );
            },
            onExceptionPressed: () {
              if (isDriver) {
                viewModel.openCantFetchPanel(sub);
              } else {
                viewModel.openNoNeedFetchPanel(sub);
              }
            },
            isCompletedToday: isCompletedToday,
            // PREVENT MULTIPLE COMPLETIONS: If already completed today, pass null to disable the button
            onCompleteTripPressed: (isDriver && !isCompletedToday) ? () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Complete Trip?'),
                  content: const Text(
                    'Mark today\'s tumpang as completed? Both you and the passenger will earn reward points.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
                  ],
                ),
              );
              if (confirmed == true) {
                // CORRECT WAY TO CALL IT:
                final success = await viewModel.completeTrip(
                  subscriptionId: sub['id'],
                  driverId: sub['driver_id'],
                  passengerId: sub['passenger_id'],
                  pickupLat: sub['pickup_lat'] ?? 0.0,
                  pickupLng: sub['pickup_lng'] ?? 0.0,
                  dropoffLat: sub['dropoff_lat'] ?? 0.0,
                  dropoffLng: sub['dropoff_lng'] ?? 0.0,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(success ? 'Trip completed! Points awarded.' : 'Failed to complete trip.')),
                  );
                }
                await viewModel.fetchCurrentUser();
              }
            } : null,
          ),
          if (index != viewModel.activeSubscriptions.length - 1)
            const SizedBox(height: 16),
        ],
      );
    });
  }
}