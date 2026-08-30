import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/propose_value_bottom_sheet.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/negotiation_field_row.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/negotiation_summary_card.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/route_map_header.dart';

// Converted to StatefulWidget to allow manual refreshing without Realtime
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

  void _openProposalSheet(
      BuildContext context,
      NegotiationViewModel controller,
      String title,
      String currentValue,
      String fieldPrefix,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ProposeValueBottomSheet(
          title: title,
          currentValue: currentValue,
          onSubmit: (newValue) async {
            final parsedFee = double.tryParse(newValue);
            if (fieldPrefix == 'fee' && parsedFee == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a valid fee amount.')),
              );
              return;
            }

            final dynamic valueToSubmit = fieldPrefix == 'fee' ? parsedFee! : newValue;

            await controller.proposeNewTerm(
              requestId: widget.requestId,
              fieldPrefix: fieldPrefix,
              value: valueToSubmit,
            );
          },
        );
      },
    ).then((_) {
      // Refresh the screen after the bottom sheet closes
      if (mounted) setState(() {});
    });
  }

  Future<void> _openDateRangePicker(
      BuildContext context,
      NegotiationViewModel controller,
      String currentStartDate,
      String currentEndDate,
      ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime initialStart = DateTime.tryParse(currentStartDate) ?? today;
    DateTime initialEnd = DateTime.tryParse(currentEndDate) ?? today.add(const Duration(days: 30));

    if (initialStart.isBefore(today)) initialStart = today;
    if (initialEnd.isBefore(initialStart)) initialEnd = initialStart.add(const Duration(days: 1));

    final DateTimeRange? pickedRange = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryYellow,
              onPrimary: AppColors.black,
              onSurface: AppColors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedRange != null) {
      final formattedStart =
          "${pickedRange.start.year}-${pickedRange.start.month.toString().padLeft(2, '0')}-${pickedRange.start.day.toString().padLeft(2, '0')}";
      final formattedEnd =
          "${pickedRange.end.year}-${pickedRange.end.month.toString().padLeft(2, '0')}-${pickedRange.end.day.toString().padLeft(2, '0')}";

      await controller.proposeNewTerm(
        requestId: widget.requestId,
        fieldPrefix: 'sub_start',
        value: formattedStart,
      );

      await controller.proposeNewTerm(
        requestId: widget.requestId,
        fieldPrefix: 'sub_end',
        value: formattedEnd,
      );

      // Refresh the screen after dates are submitted
      if (mounted) setState(() {});
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
      // Switched to FutureBuilder to match the Realtime OFF ViewModel
      body: FutureBuilder<TumpangRequest?>(
        future: controller.getSingleRequest(widget.requestId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final request = snapshot.data;
          if (request == null) {
            return const Center(child: Text('Request no longer exists.'));
          }

          final targetTripId = isDriver ? request.passengerTripId : request.driverTripId;

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
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.greyBorder, width: 1),
                      ),
                      child: const Icon(Icons.person, size: 50, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      displayName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),

                    NegotiationFieldRow(
                      title: 'Pickup Location',
                      value: request.pickupLocation.name,
                      isAccepted: request.pickupLocation.isAccepted,
                      isRequestedByMe: request.pickupLocation.requestedBy == controller.currentUserId,
                      topWidget: RouteMapHeader(
                        label: request.pickupLocation.name,
                        lat: request.pickupLocation.lat,
                        lng: request.pickupLocation.lng,
                      ),
                      onPropose: () => _openProposalSheet(
                        context, controller, 'Pickup Location', request.pickupLocation.name, 'pickup',
                      ),
                      onAccept: () async {
                        await controller.acceptTerm(widget.requestId, 'pickup');
                        if (mounted) setState(() {});
                      },
                    ),

                    NegotiationFieldRow(
                      title: 'Dropoff Location',
                      value: request.dropoffLocation.name,
                      isAccepted: request.dropoffLocation.isAccepted,
                      isRequestedByMe: request.dropoffLocation.requestedBy == controller.currentUserId,
                      topWidget: RouteMapHeader(
                        label: request.dropoffLocation.name,
                        lat: request.dropoffLocation.lat,
                        lng: request.dropoffLocation.lng,
                      ),
                      onPropose: () => _openProposalSheet(
                        context, controller, 'Dropoff Location', request.dropoffLocation.name, 'dropoff',
                      ),
                      onAccept: () async {
                        await controller.acceptTerm(widget.requestId, 'dropoff');
                        if (mounted) setState(() {});
                      },
                    ),

                    NegotiationFieldRow(
                      title: 'Tumpang Date',
                      value: '${request.subscriptionStartDate.value} to ${request.subscriptionEndDate.value}',
                      isAccepted: request.subscriptionStartDate.isAccepted && request.subscriptionEndDate.isAccepted,
                      isRequestedByMe: request.subscriptionStartDate.requestedBy == controller.currentUserId,
                      onPropose: () => _openDateRangePicker(
                        context, controller, request.subscriptionStartDate.value, request.subscriptionEndDate.value,
                      ),
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
                      onPropose: () => _openProposalSheet(
                        context, controller, 'Pickup Time', request.pickupTime.value, 'pickup_time',
                      ),
                      onAccept: () async {
                        await controller.acceptTerm(widget.requestId, 'pickup_time');
                        if (mounted) setState(() {});
                      },
                    ),

                    NegotiationFieldRow(
                      title: 'Tumpang Fee (RM)',
                      value: request.fee.value.toStringAsFixed(2),
                      isAccepted: request.fee.isAccepted,
                      isRequestedByMe: request.fee.requestedBy == controller.currentUserId,
                      onPropose: () => _openProposalSheet(
                        context, controller, 'Fee (RM)', request.fee.value.toString(), 'fee',
                      ),
                      onAccept: () async {
                        await controller.acceptTerm(widget.requestId, 'fee');
                        if (mounted) setState(() {});
                      },
                    ),

                    NegotiationSummaryCard(
                      request: request,
                      onReject: () async {
                        await controller.rejectEntireRequest(widget.requestId);
                        if (mounted) Navigator.pop(context);
                      },
                      onAccept: () async {
                        bool success = await controller.finalizeAgreement(request);
                        if (success && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Agreement Finalized!')),
                          );
                        } else if (!success && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('All terms must be accepted first.')),
                          );
                        }
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