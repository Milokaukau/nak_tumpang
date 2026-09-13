import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/trips/view_models/my_trips_view_model.dart';
import 'package:nak_tumpang/features/trips/UI/add_edit_trip_screen.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/negotiation_screen.dart';
import 'package:nak_tumpang/features/subscriptions/UI/screens/subscription_detail_screen.dart';

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MyTripsViewModel>().loadMyTrips();
    });
  }

  void _confirmDelete(BuildContext context, String tripId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Trip'),
        content: const Text('Are you sure you want to delete this trip?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.black))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);

              if (NetworkService.isOfflineNotifier.value) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cannot remove trips while offline.'), backgroundColor: Colors.red),
                );
                return;
              }

              final success = await context.read<MyTripsViewModel>().removeTrip(tripId);
              if (!context.mounted) return;

              if (success) {
                context.read<HomeViewModel>().removeLocalTrip(tripId);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? 'Trip removed successfully.' : 'Failed to remove trip.'),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleViewDetails(BuildContext context, String tripId, TripStatus status, String role) async {
    if (NetworkService.isOfflineNotifier.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot view details while offline.'), backgroundColor: Colors.red),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow)),
    );

    final vm = context.read<MyTripsViewModel>();

    try {
      if (status == TripStatus.negotiating) {
        final reqId = await vm.getNegotiatingRequestId(tripId);
        if (!context.mounted) return;
        Navigator.pop(context); // close dialog

        if (reqId != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => NegotiationScreen(requestId: reqId)));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request not found or no longer negotiating.')));
        }
      } else if (status == TripStatus.active) {
        // Pass the role to the ViewModel so it handles normalization
        final normalizedData = await vm.getActiveSubscription(tripId, role);

        if (!context.mounted) return;
        Navigator.pop(context); // close dialog

        if (normalizedData != null) {
          final currentUserId = context.read<HomeViewModel>().currentUserId ?? '';

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SubscriptionDetailScreen(
                subscription: normalizedData, // Pass the already-clean data
                currentUserId: currentUserId,
                role: role,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscription not found or no longer active.')));
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading details: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MyTripsViewModel>();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('My Trips', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.white,
        iconTheme: const IconThemeData(color: AppColors.black),
        elevation: 0,
      ),
      body: viewModel.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
          : viewModel.myTrips.isEmpty
          ? const Center(child: Text('You have no trips yet.', style: TextStyle(color: AppColors.greyText, fontSize: 16)))
          : ListView.separated(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 88,
        ),
        itemCount: viewModel.myTrips.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final trip = viewModel.myTrips[index];
          final status = viewModel.getTripStatus(trip['id']);
          return _buildTripCard(context, trip, status, viewModel.currentUserRole);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryYellow,
        onPressed: () {
          if (NetworkService.isOfflineNotifier.value) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cannot create trips while offline.'), backgroundColor: Colors.red),
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddEditTripScreen()),
          );
        },
        icon: const Icon(Icons.add, color: AppColors.black),
        label: const Text('New Trip', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
      ),
    );
  }

  String _formatTime(dynamic rawTime) {
    if (rawTime == null) return '--:--';
    final parts = rawTime.toString().split(':');
    if (parts.length < 2) return '--:--';
    return '${parts[0]}:${parts[1]}';
  }

  Widget _buildStatusBadge(TripStatus status) {
    Color color;
    String text;

    switch (status) {
      case TripStatus.active:
        color = Colors.green;
        text = 'Active Tumpang Subscription';
        break;
      case TripStatus.negotiating:
        color = Colors.orange;
        text = 'Negotiating Tumpang Subscription';
        break;
      case TripStatus.none:
        color = AppColors.greyText;
        text = 'No Active Tumpang Subscription';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTripCard(BuildContext context, Map<String, dynamic> trip, TripStatus status, String role) {
    final rawTime = role == 'driver' ? trip['depart_time'] : trip['desired_pickup_time'];
    final formattedTime = _formatTime(rawTime);

    final startLocation = role == 'driver' ? trip['depart_name'] : trip['pickup_name'];
    final endLocation = role == 'driver' ? trip['arrival_name'] : trip['dropoff_name'];
    final startStr = startLocation ?? 'Unknown Origin';
    final endStr = endLocation ?? 'Unknown Destination';

    final isLocked = status == TripStatus.active || status == TripStatus.negotiating;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyBorder),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trip['trip_name'] ?? 'Unnamed Trip',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          _buildStatusBadge(status),
          const SizedBox(height: 16),

          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: AppColors.primaryYellow),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$startStr  →  $endStr', style: const TextStyle(fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: AppColors.primaryYellow),
              const SizedBox(width: 8),
              Text(formattedTime, style: const TextStyle(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: BaseButton(
                  text: 'Edit',
                  onPressed: () {
                    if (isLocked) {
                      final msg = status == TripStatus.active
                          ? 'Cannot edit a trip that is currently subscribed.'
                          : 'Cannot edit a trip while a request is negotiating.';
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
                      return;
                    }
                    if (NetworkService.isOfflineNotifier.value) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cannot edit trips while offline.'), backgroundColor: Colors.red),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddEditTripScreen(existingTrip: trip),
                      ),
                    );
                  },
                  isOutlined: true,
                  height: 40,
                  foregroundColor: isLocked ? Colors.grey[400] : AppColors.black,
                  borderColor: isLocked ? Colors.grey[300]! : AppColors.greyBorder,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BaseButton(
                  text: 'Remove',
                  onPressed: () {
                    if (isLocked) {
                      final msg = status == TripStatus.active
                          ? 'Cannot remove a trip that is currently subscribed.'
                          : 'Cannot remove a trip while a request is negotiating.';
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
                      return;
                    }
                    _confirmDelete(context, trip['id']);
                  },
                  isOutlined: true,
                  height: 40,
                  foregroundColor: isLocked ? Colors.grey[400] : Colors.red,
                  borderColor: isLocked ? Colors.grey[300]! : Colors.red[200]!,
                ),
              ),
            ],
          ),
          if (isLocked) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: BaseButton(
                text: status == TripStatus.active ? 'View Subscription' : 'View Request',
                onPressed: () => _handleViewDetails(context, trip['id'], status, role),
              ),
            ),
          ]
        ],
      ),
    );
  }
}