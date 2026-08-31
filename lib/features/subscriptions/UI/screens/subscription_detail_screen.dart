import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/features/subscriptions/view_models/subscription_view_model.dart';
import 'package:nak_tumpang/features/subscriptions/UI/components/exception_list_section.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:nak_tumpang/features/home/UI/components/cant_fetch_panel.dart';
import 'package:nak_tumpang/features/home/UI/components/no_need_fetch_panel.dart';

class SubscriptionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> subscription;
  final String currentUserId;
  final String role; // 'passenger' or 'driver'

  const SubscriptionDetailScreen({
    super.key,
    required this.subscription,
    required this.currentUserId,
    required this.role,
  });

  @override
  State<SubscriptionDetailScreen> createState() => _SubscriptionDetailScreenState();
}

class _SubscriptionDetailScreenState extends State<SubscriptionDetailScreen> {
  Key _exceptionListKey = UniqueKey();

  void _refreshExceptions() {
    setState(() => _exceptionListKey = UniqueKey());
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final refundNote = widget.role == 'driver'
        ? 'Your deposit refund policy: cancelling will refund the passenger their deposit.'
        : 'Warning: cancelling now will forfeit your deposit to the driver.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Subscription?'),
        content: Text('This cannot be undone. $refundNote'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Subscription', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final vm = context.read<SubscriptionViewModel>();
      final success = await vm.cancelSubscription(
        subscriptionId: widget.subscription['id'],
        cancelledByRole: widget.role,
      );
      if (success && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Subscription cancelled.')));
        Navigator.pop(context);
      }
    }
  }

  void _openExceptionPanel(BuildContext context) {
    final driverTrips = widget.subscription['driver_trips'] as Map<String, dynamic>?;
    final passengerTrips = widget.subscription['passenger_trips'] as Map<String, dynamic>?;
    final driverUser = driverTrips?['users'] as Map<String, dynamic>?;
    final passengerUser = passengerTrips?['users'] as Map<String, dynamic>?;

    final driverId = driverUser?['id'] ?? '';
    final passengerId = passengerUser?['id'] ?? '';
    final driverName = driverUser?['name'] ?? 'Driver';
    final passengerName = passengerUser?['name'] ?? 'Passenger';
    final driverPhone = driverUser?['phone'] ?? '';
    final passengerPhone = passengerUser?['phone'] ?? '';

    final homeVm = context.read<HomeViewModel>();
    if (widget.role == 'driver') {
      homeVm.openCantFetchPanel();
    } else {
      homeVm.openNoNeedFetchPanel();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ListView(
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
                if (widget.role == 'driver')
                  CantFetchPanel(
                    tumpangSubscriptionId: widget.subscription['id'],
                    driverId: driverId,
                    passengerName: passengerName,
                    pickupName: widget.subscription['pickup_location'] ?? '',
                    dropoffName: widget.subscription['dropoff_location'] ?? '',
                    pickupTime: widget.subscription['pickup_time'] ?? '',
                    passengerPhone: passengerPhone,
                    onSubmitted: _refreshExceptions,
                  )
                else
                  NoNeedFetchPanel(
                    tumpangSubscriptionId: widget.subscription['id'],
                    passengerId: passengerId,
                    driverName: driverName,
                    pickupName: widget.subscription['pickup_location'] ?? '',
                    dropoffName: widget.subscription['dropoff_location'] ?? '',
                    pickupTime: widget.subscription['pickup_time'] ?? '',
                    driverPhone: driverPhone,
                    onSubmitted: _refreshExceptions,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driverTrips = widget.subscription['driver_trips'] as Map<String, dynamic>?;
    final passengerTrips = widget.subscription['passenger_trips'] as Map<String, dynamic>?;
    final otherUser = widget.role == 'passenger'
        ? (driverTrips != null ? driverTrips['users'] : null)
        : (passengerTrips != null ? passengerTrips['users'] : null);

    final isActive = widget.subscription['status'] == 'active';
    final deposit = widget.subscription['deposit'];
    final depositRefunded = widget.subscription['deposit_refunded'] == true;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        foregroundColor: AppColors.black,
        title: const Text('Tumpang Details', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(otherUser?['name'] ?? 'Unknown',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${widget.subscription['pickup_location']} → ${widget.subscription['dropoff_location']}',
                style: const TextStyle(color: AppColors.greyText)),
            Text('Pickup: ${widget.subscription['pickup_time']}',
                style: const TextStyle(color: AppColors.greyText)),
            Text('Monthly fee: RM ${widget.subscription['fee']}',
                style: const TextStyle(color: AppColors.greyText)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lightYellow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Deposit: RM $deposit',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    isActive
                        ? 'Held until subscription ends.'
                        : (depositRefunded ? 'Refunded to passenger.' : 'Forfeited to driver.'),
                    style: const TextStyle(color: AppColors.greyText, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (isActive) ...[
              SizedBox(
                width: double.infinity,
                child: BaseButton(
                  text: widget.role == 'driver' ? "Can't fetch" : 'No need fetch',
                  onPressed: () => _openExceptionPanel(context),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _confirmCancel(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text('Cancel Subscription', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Text('Schedule Changes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ExceptionListSection(
              key: _exceptionListKey,
              subscriptionId: widget.subscription['id'],
              currentUserRole: widget.role,
            ),
          ],
        ),
      ),
    );
  }
}