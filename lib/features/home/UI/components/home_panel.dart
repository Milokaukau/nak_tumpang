import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/home/UI/components/back_to_subscriptions_button.dart';
import 'package:nak_tumpang/features/home/UI/components/empty_state_message.dart';
import 'package:nak_tumpang/features/home/UI/components/passenger_matching_view.dart';
import 'package:nak_tumpang/features/home/UI/components/trip_selection_dropdown.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:nak_tumpang/features/home/UI/components/active_subscription_card.dart';

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
              // Handle Bar
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

              // --- ROLE-BASED ROUTING ---
              // NOTE: 'driver' / 'passenger' are compared as raw strings in
              // several files (here, home_screen.dart's AppSidebar call,
              // and presumably the view model). Worth promoting to an
              // enum UserRole { driver, passenger } in a follow-up so a
              // typo can't silently fall through to the wrong branch.
              if (viewModel.currentUserRole == 'driver')
                ..._buildDriverView(viewModel)
              else ...[
                if (viewModel.activeSubscriptions.isNotEmpty && !viewModel.showMatchingUI)
                  ..._buildPassengerSubscriptionView(viewModel)
                else
                  const PassengerMatchingView(),
              ],
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // VIEW MODE: DRIVER
  // ==========================================
  List<Widget> _buildDriverView(HomeViewModel viewModel) {
    if (viewModel.activeSubscriptions.isNotEmpty && !viewModel.showMatchingUI) {
      return [
        const Text('My Active Subscriptions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ..._buildSubscriptionList(viewModel, isDriver: true),
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
    }
    return _buildDriverUnmatchedView(viewModel);
  }

  List<Widget> _buildDriverUnmatchedView(HomeViewModel viewModel) {
    final hasSubscriptions = viewModel.activeSubscriptions.isNotEmpty;

    if (viewModel.availableTrips.isEmpty) {
      return [
        if (hasSubscriptions)
          BackToSubscriptionsButton(onPressed: () => viewModel.toggleMatchingUI(false)),
        const EmptyStateMessage(
          message: 'You have no unmatched trips.\nAll your routes currently have passengers!',
        ),
      ];
    }

    return [
      if (hasSubscriptions)
        BackToSubscriptionsButton(onPressed: () => viewModel.toggleMatchingUI(false)),
      const TripSelectionDropdown(),
      const SizedBox(height: 32),
      const Center(
        child: Text(
          'Waiting for passenger requests...',
          style: TextStyle(color: AppColors.greyText, fontSize: 16),
        ),
      ),
    ];
  }

  // ==========================================
  // VIEW MODE: PASSENGER SUBSCRIPTIONS
  // ==========================================
  List<Widget> _buildPassengerSubscriptionView(HomeViewModel viewModel) {
    return [
      const Text('My Active Subscriptions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      ..._buildSubscriptionList(viewModel, isDriver: false),
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

  // --- Shared between driver & passenger subscription views ---
  List<Widget> _buildSubscriptionList(HomeViewModel viewModel, {required bool isDriver}) {
    final subs = viewModel.activeSubscriptions;
    return List.generate(subs.length, (index) {
      final sub = subs[index];
      return Column(
        children: [
          ActiveSubscriptionCard(
            key: ValueKey(sub['id'] ?? index),
            name: sub['name'] ?? 'Unknown',
            phone: sub['phone'] ?? '',
            imageUrl: sub['imageUrl'],
            pickupLocation: sub['pickup_location'] ?? '-',
            dropoffLocation: sub['dropoff_location'] ?? '-',
            time: sub['pickup_time'] ?? '-',
            exceptionButtonText: isDriver ? "Can't fetch at..." : 'No need tumpang at...',
            isSelected: viewModel.selectedSubscriptionId == sub['id'],
            onTap: () => viewModel.selectSubscription(sub['id']),
            onCallPressed: () => debugPrint('Calling ${sub['phone']}...'),
            onDetailsPressed: () => debugPrint('Opening details for ${sub['id']}...'),
            onExceptionPressed: () => debugPrint('Filing exception for ${sub['id']}...'),
          ),
          if (index != subs.length - 1) const SizedBox(height: 16),
        ],
      );
    });
  }
}