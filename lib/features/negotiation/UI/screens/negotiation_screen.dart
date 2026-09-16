import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/propose_value_bottom_sheet.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/date_range_proposal_bottom_sheet.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/map_screen.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/time_proposal_bottom_sheet.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/negotiation_field_row.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/negotiation_summary_card.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/route_map_header.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/tumpang_summary_screen.dart';
import 'package:nak_tumpang/features/negotiation/utils/negotiation_error.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/subscriptions/data/services/subscription_supabase_service.dart';
import 'package:nak_tumpang/features/subscriptions/UI/screens/subscription_detail_screen.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/extend_negotiation_screen.dart';

class NegotiationScreen extends StatefulWidget {
  final String requestId;

  const NegotiationScreen({
    super.key,
    required this.requestId,
  });

  @override
  State<NegotiationScreen> createState() => _NegotiationScreenState();
}

class _NegotiationScreenState extends State<NegotiationScreen> {
  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
  }

  final SubscriptionSupabaseService _subscriptionService = SubscriptionSupabaseService();

  String _formatAmPm(String dbTime) {
    if (dbTime.isEmpty) return dbTime;
    try {
      final parts = dbTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$displayHour:$minute $period';
    } catch (e) {
      return dbTime;
    }
  }

  Future<void> _runNegotiationAction(Future<void> Function() action) async {
    try {
      await action();
    } on NegotiationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kDefaultNegotiationErrorMessage), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() {});
    }
  }

  void _openProposalSheet(BuildContext context, NegotiationViewModel controller, String title, String currentValue, String fieldPrefix) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return ProposeValueBottomSheet(
          title: title,
          currentValue: currentValue,
          onSubmit: (newValue) async {
            final parsedFee = double.tryParse(newValue);
            if (fieldPrefix == 'fee' && (parsedFee == null || !parsedFee.isFinite || parsedFee <= 1.0 || parsedFee > 100.0)) {
              throw NegotiationException('Please enter a valid fee amount between RM 1 and RM 100.');
            }
            final dynamic valueToSubmit = fieldPrefix == 'fee' ? parsedFee! : newValue;
            await controller.proposeNewTerm(requestId: widget.requestId, fieldPrefix: fieldPrefix, value: valueToSubmit);
          },
        );
      },
    ).then((_) { if (mounted) setState(() {}); });
  }

  void _openLocationPicker(BuildContext context, NegotiationViewModel controller, String title, String fieldPrefix, String currentName, double currentLat, double currentLng) {
    Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          title: title,
          initialName: currentName,
          initialLat: currentLat,
          initialLng: currentLng,
        ),
      ),
    ).then((result) async {
      if (result != null) {
        await _runNegotiationAction(() => controller.proposeNewTerm(
          requestId: widget.requestId,
          fieldPrefix: fieldPrefix,
          value: result['name'],
          lat: result['lat'],
          lng: result['lng'],
        ));
      }
    });
  }

  void _openTimeProposalSheet(BuildContext context, NegotiationViewModel controller, String currentTime) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => TimeProposalBottomSheet(initialTime: currentTime),
    ).then((result) async {
      if (result != null && result is String) {
        await _runNegotiationAction(() => controller.proposeNewTerm(requestId: widget.requestId, fieldPrefix: 'pickup_time', value: result));
      }
    });
  }

  void _openDateRangeProposalSheet(BuildContext context, NegotiationViewModel controller, String currentStart, String currentEnd) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DateRangeProposalBottomSheet(initialStartDate: currentStart, initialEndDate: currentEnd),
    ).then((result) async {
      if (result != null && result is Map) {
        await _runNegotiationAction(() => controller.proposeTumpangDateRange(
          requestId: widget.requestId,
          startDate: result['start'] as String,
          endDate: result['end'] as String,
        ));
      }
    });
  }

  Future<void> _confirmReject(BuildContext context, NegotiationViewModel controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Request?'),
        content: const Text('This will permanently reject the request. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await controller.rejectEntireRequest(widget.requestId);
      if (mounted) Navigator.pop(context);
    } on NegotiationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kDefaultNegotiationErrorMessage), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmCancel(BuildContext context, NegotiationViewModel controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: const Text('Are you sure you want to cancel this pending request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await controller.cancelRequest(widget.requestId);
      if (mounted) Navigator.pop(context);
    } on NegotiationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kDefaultNegotiationErrorMessage), backgroundColor: Colors.red),
      );
    }
  }

  void _openExtendScreen(BuildContext context, String? subscriptionId) {
    if (subscriptionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't find this subscription. Please try again from the subscription details."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExtendNegotiationScreen(subscriptionId: subscriptionId),
      ),
    );
  }

  Widget _buildSubscriptionLinkCard(String? subscriptionId, bool isDriver, String currentUserId) {
    if (subscriptionId == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey(subscriptionId),
      future: _subscriptionService.fetchSubscriptionById(
        subscriptionId,
        isDriver ? 'driver' : 'passenger',
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: AppColors.primaryYellow)),
          );
        }

        final subscription = snapshot.data;
        if (subscription == null) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(top: 32),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.greyBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.successGreenText, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Negotiation Successful',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.successGreenText
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'This request is now a subscription. You can manage your schedule, report exceptions, or cancel from the subscription details.',
                style: TextStyle(color: AppColors.greyText, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: BaseButton(
                  text: 'View Subscription Details',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SubscriptionDetailScreen(
                          subscription: subscription,
                          currentUserId: currentUserId,
                          role: isDriver ? 'driver' : 'passenger',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<NegotiationViewModel>(context, listen: false);
    final isDriver = controller.currentUserRole == 'driver';

    return ValueListenableBuilder<bool>(
        valueListenable: NetworkService.isOfflineNotifier,
        builder: (context, isOffline, _) {
          return Scaffold(
            backgroundColor: AppColors.white,
            appBar: AppBar(
              title: const Text('Viewing Request', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
              backgroundColor: AppColors.primaryYellow,
              elevation: 0,
              iconTheme: const IconThemeData(color: AppColors.black),
              centerTitle: true,
            ),
            body: FutureBuilder<TumpangRequest?>(
              future: controller.getSingleRequest(widget.requestId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));

                final request = snapshot.data;
                if (request == null) return const Center(child: Text('Request no longer exists.'));

                final targetTripId = isDriver ? request.passengerTripId : request.driverTripId;
                final myTripId = isDriver ? request.driverTripId : request.passengerTripId;
                final bool isCompleted = request.status == 'completed';
                final bool isRejected = request.status == 'rejected';
                final bool isCancelled = request.status == 'cancelled';

                // Removed `|| isOffline` so the layout stays normal
                final bool isFinalized = isCompleted || isRejected || isCancelled;
                final bool fieldsReadOnly = isFinalized;

                final bool isFullyAgreed = request.fee.isAccepted &&
                    request.pickupTime.isAccepted &&
                    request.pickupLocation.isAccepted &&
                    request.dropoffLocation.isAccepted &&
                    request.subscriptionStartDate.isAccepted &&
                    request.subscriptionEndDate.isAccepted;

                return FutureBuilder<Map<String, dynamic>?>(
                  future: controller.getUserProfileByTripId(targetTripId, isDriverTrip: !isDriver),
                  builder: (context, userSnapshot) {
                    final userData = userSnapshot.data;
                    final displayName = userData?['name'] ?? userData?['full_name'] ?? 'User';
                    final avatarUrl = userData?['avatar_url'] as String?;

                    final tripName = controller.getCachedTripName(myTripId);

                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            tripName,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.black),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.greyBorder, width: 1),
                            ),
                            child: avatarUrl != null && avatarUrl.isNotEmpty
                                ? ClipRRect(
                              borderRadius: BorderRadius.circular(11), // 12 - the 1px border
                              child: Image.network(
                                avatarUrl,
                                width: 78,
                                height: 78,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 50, color: Colors.grey),
                              ),
                            )
                                : const Icon(Icons.person, size: 50, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 24),

                          NegotiationFieldRow(
                            title: 'Pickup Location',
                            value: request.pickupLocation.name,
                            isAccepted: request.pickupLocation.isAccepted,
                            isRequestedByMe: request.pickupLocation.requestedBy == controller.currentUserId,
                            isReadOnly: fieldsReadOnly,
                            isOffline: isOffline, // Passed to control button grey-out
                            topWidget: RouteMapHeader(label: request.pickupLocation.name, lat: request.pickupLocation.lat, lng: request.pickupLocation.lng),
                            onPropose: () => _openLocationPicker(context, controller, 'Pickup Location', 'pickup', request.pickupLocation.name, request.pickupLocation.lat, request.pickupLocation.lng),
                            onAccept: () => _runNegotiationAction(() => controller.acceptTerm(widget.requestId, 'pickup')),
                          ),

                          NegotiationFieldRow(
                            title: 'Dropoff Location',
                            value: request.dropoffLocation.name,
                            isAccepted: request.dropoffLocation.isAccepted,
                            isRequestedByMe: request.dropoffLocation.requestedBy == controller.currentUserId,
                            isReadOnly: fieldsReadOnly,
                            isOffline: isOffline, // Passed to control button grey-out
                            topWidget: RouteMapHeader(label: request.dropoffLocation.name, lat: request.dropoffLocation.lat, lng: request.dropoffLocation.lng),
                            onPropose: () => _openLocationPicker(context, controller, 'Dropoff Location', 'dropoff', request.dropoffLocation.name, request.dropoffLocation.lat, request.dropoffLocation.lng),
                            onAccept: () => _runNegotiationAction(() => controller.acceptTerm(widget.requestId, 'dropoff')),
                          ),

                          NegotiationFieldRow(
                            title: 'Tumpang Dates',
                            value: '${_formatDate(request.subscriptionStartDate.value)} to ${_formatDate(request.subscriptionEndDate.value)}',
                            isAccepted: request.subscriptionStartDate.isAccepted && request.subscriptionEndDate.isAccepted,
                            isRequestedByMe: request.subscriptionStartDate.requestedBy == controller.currentUserId,
                            isReadOnly: fieldsReadOnly,
                            isOffline: isOffline, // Passed to control button grey-out
                            onPropose: () => _openDateRangeProposalSheet(context, controller, request.subscriptionStartDate.value, request.subscriptionEndDate.value),
                            onAccept: () => _runNegotiationAction(() => controller.acceptTumpangDateRange(widget.requestId)),
                          ),

                          NegotiationFieldRow(
                            title: 'Pickup Time',
                            value: _formatAmPm(request.pickupTime.value),
                            isAccepted: request.pickupTime.isAccepted,
                            isRequestedByMe: request.pickupTime.requestedBy == controller.currentUserId,
                            isReadOnly: fieldsReadOnly,
                            isOffline: isOffline, // Passed to control button grey-out
                            onPropose: () => _openTimeProposalSheet(context, controller, request.pickupTime.value),
                            onAccept: () => _runNegotiationAction(() => controller.acceptTerm(widget.requestId, 'pickup_time')),
                          ),

                          NegotiationFieldRow(
                            title: 'Tumpang Fee',
                            value: 'RM ${request.fee.value.toStringAsFixed(2)}',
                            isAccepted: request.fee.isAccepted,
                            isRequestedByMe: request.fee.requestedBy == controller.currentUserId,
                            isReadOnly: fieldsReadOnly,
                            isOffline: isOffline, // Passed to control button grey-out
                            topWidget: Column(
                              children: [
                                Text(
                                  'RM ${request.fee.value.toStringAsFixed(2)}/day  x  ${request.subscriptionDays} day${request.subscriptionDays == 1 ? '' : 's'}',
                                  style: const TextStyle(fontSize: 13, color: AppColors.black),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Total: RM ${request.totalFee.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.black),
                                ),
                              ],
                            ),
                            onPropose: () => _openProposalSheet(context, controller, 'Fee (per day)', request.fee.value.toString(), 'fee'),
                            onAccept: () => _runNegotiationAction(() => controller.acceptTerm(widget.requestId, 'fee')),
                          ),

                          NegotiationSummaryCard(
                            request: request,
                            isFullyAgreed: isFullyAgreed,
                            isDriver: isDriver,
                            isReadOnly: isCompleted,
                            isRejected: isRejected || isCancelled,
                            isOffline: isOffline,
                            onReject: () => _confirmReject(context, controller),
                            onCancelRequest: () => _confirmCancel(context, controller),
                            onCancelSubscription: () => _confirmCancel(context, controller),
                            onRenew: () => _openExtendScreen(context, request.subscriptionId),
                            onRenegotiate: () => _openExtendScreen(context, request.subscriptionId),
                            onProceedToSummary: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TumpangSummaryScreen(requestId: request.id),
                                ),
                              );
                            },
                          ),
                          if (isCompleted)
                            _buildSubscriptionLinkCard(
                              request.subscriptionId,
                              isDriver,
                              controller.currentUserId ?? '',
                            ),

                          const SizedBox(height: 40),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          );
        }
    );
  }
}