import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_filter_options.dart';
import 'package:nak_tumpang/features/subscriptions/view_models/subscription_view_model.dart';
import 'package:nak_tumpang/features/subscriptions/UI/components/subscription_card.dart';
import 'subscription_detail_screen.dart';

class SubscriptionListScreen extends StatefulWidget {
  final String userId;
  final String role;

  const SubscriptionListScreen({
    super.key,
    required this.userId,
    required this.role,
  });

  @override
  State<SubscriptionListScreen> createState() => _SubscriptionListScreenState();
}

class _SubscriptionListScreenState extends State<SubscriptionListScreen> {
  String selectedFilter = 'Active';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _refresh());
  }

  Future<void> _refresh() async {
    await context.read<SubscriptionViewModel>().fetchSubscriptions(
      userId: widget.userId,
      role: widget.role,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SubscriptionViewModel>();
    final filtered = vm.subscriptions.where((s) {
      final isActive = s['status'] == 'active';
      return selectedFilter == 'Active' ? isActive : !isActive;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        foregroundColor: AppColors.black,
        title: const Text('My Tumpangs', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            BaseFilterOptions(
              options: const ['Active', 'Inactive'],
              selectedOption: selectedFilter,
              onSelectionChanged: (option) => setState(() => selectedFilter = option),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: vm.isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
                  : RefreshIndicator(
                color: AppColors.primaryYellow,
                onRefresh: _refresh,
                child: filtered.isEmpty
                    ? ListView(
                  children: const [
                    SizedBox(height: 100),
                    Center(
                      child: Text('No tumpangs found.', style: TextStyle(color: AppColors.greyText)),
                    ),
                  ],
                )
                    : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final sub = filtered[index];

                    final myTripKey = widget.role == 'passenger' ? 'passenger_trips' : 'driver_trips';
                    final myTrip = sub[myTripKey] as Map<String, dynamic>?;
                    final tripName = myTrip?['trip_name'] ?? sub['trip_name'] ?? 'Tumpang Journey';

                    return SubscriptionCard(
                      tripName: tripName,
                      name: sub['name'] ?? 'Unknown',
                      phone: sub['phone'] ?? 'N/A',
                      imageUrl: sub['imageUrl'],
                      pickupName: sub['pickup_location'] ?? '',
                      dropoffName: sub['dropoff_location'] ?? '',
                      pickupTime: sub['pickup_time'] ?? '',
                      isActive: sub['status'] == 'active',
                      hasActiveException: sub['has_active_exception'] ?? false,
                      showPayButton: widget.role == 'passenger' && sub['status'] == 'active',
                      onPayPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Redirecting to payment...'),
                          ),
                        );
                      },
                      onViewDetails: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SubscriptionDetailScreen(
                              subscription: sub,
                              currentUserId: widget.userId,
                              role: widget.role,
                            ),
                          ),
                        );
                        _refresh();
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}