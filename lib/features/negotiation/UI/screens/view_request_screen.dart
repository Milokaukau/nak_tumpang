import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/propose_value_bottom_sheet.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/date_range_proposal_bottom_sheet.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/location_picker_screen.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/time_proposal_bottom_sheet.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/negotiation_field_row.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/negotiation_summary_card.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/route_map_header.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/tumpang_summary_screen.dart'; // Ensure this is imported

class ViewRequestScreen extends StatefulWidget {
  final String requestId;

  const ViewRequestScreen({
    super.key,
    required this.requestId,
  });

  @override
  State<ViewRequestScreen> createState() => _ViewRequestScreenState();
}

class _ViewRequestScreenState extends State<ViewRequestScreen> {
  // ... (Keep the existing _openProposalSheet and _openDateRangePicker exactly as they are)[cite: 14] ...

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
            if (fieldPrefix == 'fee' && parsedFee == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid fee amount.')));
              return;
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
        builder: (context) => LocationPickerScreen(
          title: title,
          initialName: currentName,
          initialLat: currentLat,
          initialLng: currentLng,
        ),
      ),
    ).then((result) async {
      if (result != null) {
        await controller.proposeNewTerm(
          requestId: widget.requestId,
          fieldPrefix: fieldPrefix,
          value: result['name'],
          lat: result['lat'],
          lng: result['lng'],
        );
      }
      if (mounted) setState(() {});
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
        await controller.proposeNewTerm(requestId: widget.requestId, fieldPrefix: 'pickup_time', value: result);
      }
      if (mounted) setState(() {});
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
        await controller.proposeNewTerm(requestId: widget.requestId, fieldPrefix: 'sub_start', value: result['start']);
        await controller.proposeNewTerm(requestId: widget.requestId, fieldPrefix: 'sub_end', value: result['end']);
      }
      if (mounted) setState(() {});
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

    if (confirmed == true) {
      await controller.rejectEntireRequest(widget.requestId);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<NegotiationViewModel>(context, listen: false);
    final isDriver = controller.currentUserRole == 'driver';

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

          // Determine overall agreement logic for Test Cases 8 & 9
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

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.greyBorder, width: 1),
                      ),
                      child: const Icon(Icons.person, size: 50, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),

                    NegotiationFieldRow(
                      title: 'Pickup Location',
                      value: request.pickupLocation.name,
                      isAccepted: request.pickupLocation.isAccepted,
                      isRequestedByMe: request.pickupLocation.requestedBy == controller.currentUserId,
                      topWidget: RouteMapHeader(label: request.pickupLocation.name, lat: request.pickupLocation.lat, lng: request.pickupLocation.lng),
                      onPropose: () => _openLocationPicker(context, controller, 'Pickup Location', 'pickup', request.pickupLocation.name, request.pickupLocation.lat, request.pickupLocation.lng),
                      onAccept: () async { await controller.acceptTerm(widget.requestId, 'pickup'); if (mounted) setState(() {}); },
                    ),

                    NegotiationFieldRow(
                      title: 'Dropoff Location',
                      value: request.dropoffLocation.name,
                      isAccepted: request.dropoffLocation.isAccepted,
                      isRequestedByMe: request.dropoffLocation.requestedBy == controller.currentUserId,
                      topWidget: RouteMapHeader(label: request.dropoffLocation.name, lat: request.dropoffLocation.lat, lng: request.dropoffLocation.lng),
                      onPropose: () => _openLocationPicker(context, controller, 'Dropoff Location', 'dropoff', request.dropoffLocation.name, request.dropoffLocation.lat, request.dropoffLocation.lng),
                      onAccept: () async { await controller.acceptTerm(widget.requestId, 'dropoff'); if (mounted) setState(() {}); },
                    ),

                    NegotiationFieldRow(
                      title: 'Tumpang Dates',
                      value: '${request.subscriptionStartDate.value} to ${request.subscriptionEndDate.value}',
                      isAccepted: request.subscriptionStartDate.isAccepted && request.subscriptionEndDate.isAccepted,
                      isRequestedByMe: request.subscriptionStartDate.requestedBy == controller.currentUserId,
                      onPropose: () => _openDateRangeProposalSheet(context, controller, request.subscriptionStartDate.value, request.subscriptionEndDate.value),
                      onAccept: () async {
                        await controller.acceptTerm(widget.requestId, 'sub_start');
                        await controller.acceptTerm(widget.requestId, 'sub_end');
                        if (mounted) setState(() {});
                      },
                    ),

                    NegotiationFieldRow(
                      title: 'Pickup Time',
                      value: request.pickupTime.value,
                      isAccepted: request.pickupTime.isAccepted,
                      isRequestedByMe: request.pickupTime.requestedBy == controller.currentUserId,
                      onPropose: () => _openTimeProposalSheet(context, controller, request.pickupTime.value),
                      onAccept: () async { await controller.acceptTerm(widget.requestId, 'pickup_time'); if (mounted) setState(() {}); },
                    ),

                    NegotiationFieldRow(
                      title: 'Tumpang Fee',
                      value: 'RM ${request.fee.value.toStringAsFixed(2)}',
                      isAccepted: request.fee.isAccepted,
                      isRequestedByMe: request.fee.requestedBy == controller.currentUserId,
                      topWidget: Column(
                        children: [
                          Text(
                            'RM ${request.fee.value.toStringAsFixed(2)}/day  x  ${request.subscriptionDays} day${request.subscriptionDays == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 13, color: AppColors.black),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'RM ${request.totalFee.toStringAsFixed(2)} total',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.black),
                          ),
                        ],
                      ),
                      onPropose: () => _openProposalSheet(context, controller, 'Fee (per day)', request.fee.value.toStringAsFixed(2), 'fee'),
                      onAccept: () async { await controller.acceptTerm(widget.requestId, 'fee'); if (mounted) setState(() {}); },
                    ),

                    NegotiationSummaryCard(
                      request: request,
                      isFullyAgreed: isFullyAgreed,
                      isDriver: isDriver,
                      onReject: () => _confirmReject(context, controller),
                      onProceedToSummary: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TumpangSummaryScreen(requestId: request.id),
                          ),
                        );
                      },
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
}