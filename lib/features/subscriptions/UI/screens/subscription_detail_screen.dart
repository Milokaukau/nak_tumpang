import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/features/subscriptions/view_models/subscription_view_model.dart';
import 'package:nak_tumpang/features/subscriptions/UI/components/exception_list_section.dart';
import 'package:nak_tumpang/features/home/UI/components/cant_fetch_panel.dart';
import 'package:nak_tumpang/features/home/UI/components/no_need_fetch_panel.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

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
    String selectedReason = 'Schedule changed';
    final customReasonController = TextEditingController();
    final cancelReasons = [
      'Schedule changed',
      'Found alternative transport',
      'Financial reasons',
      'Personal reasons',
      'Others',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Cancel Subscription'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Please select a reason for cancellation:'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.lightYellow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selectedReason,
                      items: cancelReasons
                          .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedReason = val);
                      },
                    ),
                  ),
                ),
                if (selectedReason == 'Others') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: customReasonController,
                    decoration: InputDecoration(
                      hintText: 'Enter reason',
                      filled: true,
                      fillColor: AppColors.lightYellow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm Cancel', style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && context.mounted) {
      final reasonText =
      selectedReason == 'Others' ? customReasonController.text.trim() : selectedReason;

      final vm = context.read<SubscriptionViewModel>();
      final success = await vm.cancelSubscription(
        subscriptionId: widget.subscription['id'],
        cancelledByRole: widget.role,
        reason: reasonText,
      );

      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription cancelled successfully.')),
        );
        context.read<HomeViewModel>().refreshCurrentUserData();
        Navigator.of(context).pop(true);
      }
    }
  }

  void _openExceptionPanel(BuildContext context) {
    final driverTrips = widget.subscription['driver_trips'] as Map<String, dynamic>?;
    final passengerTrips = widget.subscription['passenger_trips'] as Map<String, dynamic>?;
    final driverUser = driverTrips?['users'] as Map<String, dynamic>?;
    final passengerUser = passengerTrips?['users'] as Map<String, dynamic>?;

    final driverId = widget.subscription['driver_id'] ??
        (widget.role == 'driver' ? widget.currentUserId : (driverUser?['id'] ?? ''));
    final passengerId = widget.subscription['passenger_id'] ??
        (widget.role == 'passenger' ? widget.currentUserId : (passengerUser?['id'] ?? ''));
    final driverName = widget.subscription['driver_name'] ?? driverUser?['name'] ?? widget.subscription['name'] ?? 'Driver';
    final passengerName = widget.subscription['passenger_name'] ?? passengerUser?['name'] ?? widget.subscription['name'] ?? 'Passenger';
    final driverPhone = widget.subscription['driver_phone'] ?? driverUser?['phone'] ?? widget.subscription['phone'] ?? '';
    final passengerPhone = widget.subscription['passenger_phone'] ?? passengerUser?['phone'] ?? widget.subscription['phone'] ?? '';

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
                    minDate: DateTime.tryParse(widget.subscription['subscription_start_date'] ?? ''),
                    maxDate: DateTime.tryParse(widget.subscription['subscription_end_date'] ?? ''),
                    passengerPhone: passengerPhone,
                    onSubmitted: () {
                      Navigator.of(context).pop();
                      _refreshExceptions();
                    },
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
                    minDate: DateTime.tryParse(widget.subscription['subscription_start_date'] ?? ''),
                    maxDate: DateTime.tryParse(widget.subscription['subscription_end_date'] ?? ''),
                    onSubmitted: () {
                      Navigator.of(context).pop();
                      _refreshExceptions();
                    },
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
    final isActive = widget.subscription['status'] == 'active';
    final deposit = widget.subscription['deposit'] ?? '0';
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.subscription['name'] ?? 'Unknown',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.shade100 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isActive ? 'ACTIVE' : 'INACTIVE',
                    style: TextStyle(
                      color: isActive ? Colors.green.shade800 : Colors.grey.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${widget.subscription['pickup_location']} → ${widget.subscription['dropoff_location']}',
                style: const TextStyle(color: AppColors.greyText)),
            Text('Pickup: ${widget.subscription['pickup_time']}',
                style: const TextStyle(color: AppColors.greyText)),
            if (widget.subscription['fee'] != null)
              Text('Daily fee: RM ${widget.subscription['fee']}',
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

            // ONLY DISPLAY CRUD ACTION BUTTONS IF SUBSCRIPTION IS ACTIVE
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
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'This subscription is inactive. Modifications are disabled.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.greyText, fontStyle: FontStyle.italic),
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
              fee: double.tryParse(widget.subscription['fee']?.toString() ?? ''),
              isActive: isActive,
              minDate: DateTime.tryParse(widget.subscription['subscription_start_date'] ?? ''),
              maxDate: DateTime.tryParse(widget.subscription['subscription_end_date'] ?? ''),
            ),
          ],
        ),
      ),
    );
  }
}