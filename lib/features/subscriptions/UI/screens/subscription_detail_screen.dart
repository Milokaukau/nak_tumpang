import 'package:flutter/material.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/extend_negotiation_screen.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/features/subscriptions/view_models/subscription_view_model.dart';
import 'package:nak_tumpang/features/home/UI/components/cant_fetch_panel.dart';
import 'package:nak_tumpang/features/home/UI/components/no_need_fetch_panel.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/route_map_header.dart';
import 'package:nak_tumpang/features/subscriptions/UI/components/edit_exception_sheet.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/subscriptions/data/services/subscription_local_service.dart';

class SubscriptionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> subscription;
  final String currentUserId;
  final String role;
  final int initialTabIndex;

  const SubscriptionDetailScreen({
    super.key,
    required this.subscription,
    required this.currentUserId,
    required this.role,
    this.initialTabIndex = 0,
  });

  @override
  State<SubscriptionDetailScreen> createState() => _SubscriptionDetailScreenState();
}

class _SubscriptionDetailScreenState extends State<SubscriptionDetailScreen>
    with SingleTickerProviderStateMixin {
  final SubscriptionLocalService _subscriptionLocalService = SubscriptionLocalService();
  late final TabController _tabController;
  Key _exceptionListKey = UniqueKey();
  List<Map<String, dynamic>> _exceptions = [];
  bool _isLoadingExceptions = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchExceptions();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchExceptions() async {
    setState(() => _isLoadingExceptions = true);
    final subscriptionId = widget.subscription['id'];

    if (NetworkService.isOfflineNotifier.value) {
      final cached = await _subscriptionLocalService.getAllCachedExceptions(subscriptionId);
      if (mounted) {
        setState(() {
          _exceptions = cached;
          _isLoadingExceptions = false;
        });
      }
      return;
    }

    try {
      final vm = context.read<SubscriptionViewModel>();
      final fetched = await vm.fetchAllExceptions(subscriptionId);

      try {
        await _subscriptionLocalService.cacheExceptions(
          subscriptionId: subscriptionId,
          exceptions: fetched,
        );
      } catch (e) {
        debugPrint('⚠️ Error caching exceptions locally: $e');
      }

      if (mounted) {
        setState(() {
          _exceptions = fetched;
          _isLoadingExceptions = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching exceptions, falling back to cache: $e');
      final cached = await _subscriptionLocalService.getAllCachedExceptions(subscriptionId);
      if (mounted) {
        setState(() {
          _exceptions = cached;
          _isLoadingExceptions = false;
        });
      }
    }
  }

  void _refreshExceptions() {
    setState(() => _exceptionListKey = UniqueKey());
    _fetchExceptions();
  }

  bool _isWithinExtendWindow() {
    if (widget.subscription['ended_by'] != 'natural') return false;
    final endDateStr = widget.subscription['subscription_end_date'];
    final endDate = DateTime.tryParse(endDateStr ?? '');
    if (endDate == null) return false;

    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final daysPastExpiry = todayDateOnly.difference(endDate).inDays;

    return daysPastExpiry >= 0 && daysPastExpiry <= 7;
  }

  String _otherUserId() {
    final driverTrips = widget.subscription['driver_trips'] as Map<String, dynamic>?;
    final passengerTrips = widget.subscription['passenger_trips'] as Map<String, dynamic>?;
    final driverUser = driverTrips?['users'] as Map<String, dynamic>?;
    final passengerUser = passengerTrips?['users'] as Map<String, dynamic>?;

    final driverId = widget.subscription['driver_id'] ??
        (widget.role == 'driver' ? widget.currentUserId : (driverUser?['id'] ?? ''));
    final passengerId = widget.subscription['passenger_id'] ??
        (widget.role == 'passenger' ? widget.currentUserId : (passengerUser?['id'] ?? ''));

    return widget.role == 'driver' ? (passengerId ?? '') : (driverId ?? '');
  }

  Future<void> _handleExtend(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExtendNegotiationScreen(
          subscriptionId: widget.subscription['id'],
        ),
      ),
    );
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Cancel Subscription', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Please select a reason for cancellation:'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: AppColors.lightYellow, borderRadius: BorderRadius.circular(8)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selectedReason,
                      items: cancelReasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back', style: TextStyle(color: Colors.grey))),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm Cancel', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && context.mounted) {
      final reasonText = selectedReason == 'Others' ? customReasonController.text.trim() : selectedReason;
      final vm = context.read<SubscriptionViewModel>();

      final success = await vm.cancelSubscription(
        subscriptionId: widget.subscription['id'],
        cancelledByRole: widget.role,
        reason: reasonText,
      );

      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscription cancelled successfully.')));
        context.read<HomeViewModel>().fetchCurrentUser();
        Navigator.of(context).pop(true);
      }
    }
  }

  void _openExceptionPanel(BuildContext context) {
    final driverTrips = widget.subscription['driver_trips'] as Map<String, dynamic>?;
    final passengerTrips = widget.subscription['passenger_trips'] as Map<String, dynamic>?;
    final driverUser = driverTrips?['users'] as Map<String, dynamic>?;
    final passengerUser = passengerTrips?['users'] as Map<String, dynamic>?;

    final driverId = widget.subscription['driver_id'] ?? (widget.role == 'driver' ? widget.currentUserId : (driverUser?['id'] ?? ''));
    final passengerId = widget.subscription['passenger_id'] ?? (widget.role == 'passenger' ? widget.currentUserId : (passengerUser?['id'] ?? ''));
    final driverName = widget.subscription['driver_name'] ?? driverUser?['name'] ?? widget.subscription['name'] ?? 'Driver';
    final passengerName = widget.subscription['passenger_name'] ?? passengerUser?['name'] ?? widget.subscription['name'] ?? 'Passenger';
    final driverPhone = widget.subscription['driver_phone'] ?? driverUser?['phone'] ?? widget.subscription['phone'] ?? '';
    final passengerPhone = widget.subscription['passenger_phone'] ?? passengerUser?['phone'] ?? '';

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
                    height: 4, width: 40,
                    decoration: BoxDecoration(color: AppColors.greyBorder, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                if (widget.role == 'driver')
                  CantFetchPanel(
                    tumpangSubscriptionId: widget.subscription['id'],
                    driverId: driverId,
                    passengerId: passengerId,
                    passengerName: passengerName,
                    pickupName: widget.subscription['pickup_location'] ?? '',
                    dropoffName: widget.subscription['dropoff_location'] ?? '',
                    pickupTime: widget.subscription['pickup_time'] ?? '',
                    minDate: DateTime.tryParse(widget.subscription['subscription_start_date'] ?? ''),
                    maxDate: DateTime.tryParse(widget.subscription['subscription_end_date'] ?? ''),
                    passengerPhone: passengerPhone,
                    onSubmitted: () async {
                      Navigator.of(context).pop();
                      _refreshExceptions();
                      await context.read<HomeViewModel>().sendExceptionNotification(
                        targetUserId: passengerId ?? '',
                        title: 'New Schedule Exception Request',
                        message: 'Driver submitted a schedule exception request.',
                        subscriptionId: widget.subscription['id'],
                      );
                    },
                  )
                else
                  NoNeedFetchPanel(
                    tumpangSubscriptionId: widget.subscription['id'],
                    passengerId: passengerId,
                    driverId: driverId,
                    driverName: driverName,
                    pickupName: widget.subscription['pickup_location'] ?? '',
                    dropoffName: widget.subscription['dropoff_location'] ?? '',
                    pickupTime: widget.subscription['pickup_time'] ?? '',
                    driverPhone: driverPhone,
                    minDate: DateTime.tryParse(widget.subscription['subscription_start_date'] ?? ''),
                    maxDate: DateTime.tryParse(widget.subscription['subscription_end_date'] ?? ''),
                    onSubmitted: () async {
                      Navigator.of(context).pop();
                      _refreshExceptions();
                      await context.read<HomeViewModel>().sendExceptionNotification(
                        targetUserId: driverId ?? '',
                        title: 'New Schedule Exception Request',
                        message: 'Passenger submitted a schedule exception request.',
                        subscriptionId: widget.subscription['id'],
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openEditException(Map<String, dynamic> exception) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditExceptionSheet(
        exception: exception,
        otherUserId: _otherUserId(),
        onChanged: _refreshExceptions,
        minDate: DateTime.tryParse(widget.subscription['subscription_start_date'] ?? ''),
        maxDate: DateTime.tryParse(widget.subscription['subscription_end_date'] ?? ''),
      ),
    );
  }

  String _formatAmPm(String dbTime) {
    if (dbTime.isEmpty) return dbTime;
    try {
      final parts = dbTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute';
    } catch (e) {
      return dbTime;
    }
  }

  Widget _buildReadOnlyField({required String title, required String value, Widget? topWidget}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topWidget != null) topWidget,
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.lock, size: 16, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(value, style: const TextStyle(fontSize: 14, color: AppColors.black)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(BuildContext context, bool isActive) {
    final endedBy = widget.subscription['ended_by'];
    final cancelReason = widget.subscription['cancellation_reason'];

    final myTripKey = widget.role == 'passenger' ? 'passenger_trips' : 'driver_trips';
    final myTrip = widget.subscription[myTripKey] as Map<String, dynamic>?;
    final tripName = myTrip?['trip_name'] ?? widget.subscription['trip_name'] ?? 'Tumpang Journey';
    final otherUserName = widget.subscription['name'] ?? 'User';
    final otherImageUrl = widget.subscription['imageUrl'] as String?;
    final pickupName = widget.subscription['pickup_location'] ?? 'Unknown';
    final dropoffName = widget.subscription['dropoff_location'] ?? 'Unknown';
    final startDate = widget.subscription['subscription_start_date'] ?? '';
    final endDate = widget.subscription['subscription_end_date'] ?? '';
    final pickupTime = widget.subscription['pickup_time'] ?? '';

    final fee = double.tryParse(widget.subscription['fee']?.toString() ?? '0') ?? 0.0;
    int days = 1;
    final startDt = DateTime.tryParse(startDate);
    final endDt = DateTime.tryParse(endDate);
    if (startDt != null && endDt != null) {
      days = endDt.difference(startDt).inDays + 1;
    }
    final totalFee = fee * days;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            tripName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.black),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          if (!isActive)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      const Text('Subscription Inactive', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  if (endedBy != null && endedBy != 'natural') ...[
                    const SizedBox(height: 8),
                    Text('Cancelled by: ${endedBy.toString().toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.black)),
                    if (cancelReason != null && cancelReason.toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Reason: $cancelReason', style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.greyText)),
                      ),
                  ],
                ],
              ),
            ),

          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.greyBorder, width: 1),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: otherImageUrl != null && otherImageUrl.isNotEmpty
                ? ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.network(
                otherImageUrl,
                width: 78,
                height: 78,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 44, color: Colors.grey),
              ),
            )
                : const Icon(Icons.person, size: 44, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          Text(otherUserName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          _buildReadOnlyField(
            title: 'Pickup Location',
            value: pickupName,
            topWidget: RouteMapHeader(
              label: pickupName,
              lat: double.tryParse(widget.subscription['pickup_lat']?.toString() ?? '0') ?? 0.0,
              lng: double.tryParse(widget.subscription['pickup_lng']?.toString() ?? '0') ?? 0.0,
            ),
          ),

          _buildReadOnlyField(
            title: 'Dropoff Location',
            value: dropoffName,
            topWidget: RouteMapHeader(
              label: dropoffName,
              lat: double.tryParse(widget.subscription['dropoff_lat']?.toString() ?? '0') ?? 0.0,
              lng: double.tryParse(widget.subscription['dropoff_lng']?.toString() ?? '0') ?? 0.0,
            ),
          ),

          _buildReadOnlyField(
            title: 'Tumpang Dates',
            value: '$startDate to $endDate',
          ),

          _buildReadOnlyField(
            title: 'Pickup Time',
            value: _formatAmPm(pickupTime),
          ),

          _buildReadOnlyField(
            title: 'Tumpang Fee',
            value: 'RM ${fee.toStringAsFixed(2)}',
            topWidget: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: const BoxDecoration(
                color: AppColors.lightYellow,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                children: [
                  Text('RM ${fee.toStringAsFixed(2)}/day  x  $days day${days == 1 ? '' : 's'}', style: const TextStyle(fontSize: 13, color: AppColors.black)),
                  const SizedBox(height: 4),
                  Text('Total: RM ${totalFee.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.black)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

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
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Colors.red),
                ),
                child: const Text('Cancel Subscription', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ),
          ] else if (_isWithinExtendWindow()) ...[
            SizedBox(
              width: double.infinity,
              child: BaseButton(
                text: 'Extend Your Subscription?',
                onPressed: () => _handleExtend(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${7 - DateTime.now().difference(DateTime.tryParse(widget.subscription['subscription_end_date'] ?? '') ?? DateTime.now()).inDays} day(s) left to extend',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.greyText),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildScheduleChangesTab(bool isActive) {
    if (_isLoadingExceptions) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow));
    }

    final myUserId = widget.currentUserId.toString();
    final myRole = widget.role.toLowerCase();

    final driverChanges = _exceptions.where((e) {
      final role = e['initiated_by_role']?.toString().toLowerCase();
      final userId = e['initiated_by']?.toString();
      return role == 'driver' || (myRole == 'driver' && userId == myUserId);
    }).toList();

    final passengerChanges = _exceptions.where((e) {
      final role = e['initiated_by_role']?.toString().toLowerCase();
      final userId = e['initiated_by']?.toString();
      return role == 'passenger' || (myRole == 'passenger' && userId == myUserId);
    }).toList();

    final isDriver = myRole == 'driver';
    final myItems = isDriver ? driverChanges : passengerChanges;
    final otherItems = isDriver ? passengerChanges : driverChanges;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: AppColors.lightYellow.withOpacity(0.4),
            child: TabBar(
              labelColor: AppColors.black,
              unselectedLabelColor: AppColors.greyText,
              indicatorColor: AppColors.primaryYellow,
              indicatorWeight: 3,
              tabs: [
                Tab(text: isDriver ? 'Driver Changes' : 'Passenger Changes'),
                Tab(text: isDriver ? 'Passenger Changes' : 'Driver Changes'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildExceptionList(myItems, isMyChanges: true, isActive: isActive),
                _buildExceptionList(otherItems, isMyChanges: false, isActive: isActive),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExceptionList(List<Map<String, dynamic>> items, {required bool isMyChanges, required bool isActive}) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_note_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                isMyChanges ? 'You have not created any exception requests.' : 'No exception requests from the other party.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.greyText, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final dailyFee = double.tryParse(widget.subscription['fee']?.toString() ?? '') ?? 0.0;
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final status = item['status'] ?? 'pending';
        final reason = item['reason'] ?? item['note'] ?? 'Schedule exception';
        final initiatedByRole = item['initiated_by_role']?.toString().toLowerCase();

        final startDate = item['start_date'] ?? '';
        final endDate = item['end_date'] ?? '';
        final dateText = (endDate.isNotEmpty && endDate != startDate)
            ? '$startDate → $endDate'
            : startDate;

        final parsedEndDate = DateTime.tryParse(endDate);
        final isPast = parsedEndDate != null && parsedEndDate.isBefore(todayDateOnly);

        Color statusColor;
        String displayStatus;
        if (isPast) {
          statusColor = Colors.grey;
          displayStatus = 'PAST';
        } else {
          statusColor = Colors.orange;
          if (status == 'approved' || status == 'accepted' || status == 'active') statusColor = Colors.green;
          if (status == 'rejected') statusColor = Colors.red;
          displayStatus = status.toUpperCase();
        }

        double? refundAmount;
        int? exceptionDays;
        if (initiatedByRole == 'driver' && status == 'active' && !isPast) {
          final start = DateTime.tryParse(startDate);
          final end = DateTime.tryParse(endDate);
          if (start != null && end != null) {
            exceptionDays = end.difference(start).inDays + 1;
            refundAmount = exceptionDays * dailyFee;
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.greyBorder),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('Date: $dateText', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      displayStatus,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Reason: $reason', style: const TextStyle(color: AppColors.black, fontSize: 13)),

              if (refundAmount != null && refundAmount > 0) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.successGreenBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.savings_outlined, size: 16, color: AppColors.successGreenText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.role == 'passenger'
                              ? 'RM ${refundAmount.toStringAsFixed(2)} will be deducted from your next invoice '
                              '($exceptionDays day${exceptionDays == 1 ? '' : 's'} × RM ${dailyFee.toStringAsFixed(2)}/day).'
                              : 'This reduces the passenger\'s next invoice by RM ${refundAmount.toStringAsFixed(2)} '
                              '($exceptionDays day${exceptionDays == 1 ? '' : 's'} × RM ${dailyFee.toStringAsFixed(2)}/day).',
                          style: const TextStyle(color: AppColors.successGreenText, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (isMyChanges && status == 'active' && isActive && !isPast) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: BaseButton(text: 'Edit', onPressed: () => _openEditException(item)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.subscription['status'] == 'active';

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        foregroundColor: AppColors.black,
        centerTitle: true,
        title: const Text('Tumpang Details', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.black,
          unselectedLabelColor: AppColors.greyText,
          indicatorColor: AppColors.black,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Schedule Changes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(context, isActive),
          _buildScheduleChangesTab(isActive),
        ],
      ),
    );
  }
}