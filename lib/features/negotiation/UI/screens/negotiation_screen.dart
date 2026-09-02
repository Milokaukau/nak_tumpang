import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
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
  /// Shared error-handling wrapper for every negotiation mutation fired
  /// from this screen (propose/accept for each field, the atomic date
  /// range, and reject). Every one of these already throws
  /// [NegotiationException] with a safe, user-facing message on failure
  /// (see NegotiationViewModel / runNegotiationAction) - this is just the
  /// one place that catches it, shows it, and refreshes the UI, so each
  /// button doesn't need its own try/catch.
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
            if (fieldPrefix == 'fee' && parsedFee == null) {
              throw NegotiationException('Please enter a valid fee amount.');
            }
            final dynamic valueToSubmit = fieldPrefix == 'fee' ? parsedFee! : newValue;
            // Errors here (NegotiationException or otherwise) propagate up
            // through ProposeValueBottomSheet's own try/catch, which shows
            // them inline in the still-open sheet and lets the user retry
            // without losing what they typed.
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

  /// Opens the combined Tumpang Dates picker and submits both dates as a
  /// single atomic proposal (NegotiationViewModel.proposeTumpangDateRange
  /// -> the `propose_tumpang_dates` RPC), instead of two separate
  /// `proposeNewTerm('sub_start', ...)` / `proposeNewTerm('sub_end', ...)`
  /// calls that could leave the request half-updated if the second call
  /// never completed.
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

    // Deliberately not using _runNegotiationAction here: on success we need
    // to pop this whole screen (the request no longer exists to view)
    // rather than just refresh it, and on failure we must NOT pop - the
    // user needs to stay on the screen and be able to retry.
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
                      onAccept: () => _runNegotiationAction(() => controller.acceptTerm(widget.requestId, 'pickup')),
                    ),

                    NegotiationFieldRow(
                      title: 'Dropoff Location',
                      value: request.dropoffLocation.name,
                      isAccepted: request.dropoffLocation.isAccepted,
                      isRequestedByMe: request.dropoffLocation.requestedBy == controller.currentUserId,
                      topWidget: RouteMapHeader(label: request.dropoffLocation.name, lat: request.dropoffLocation.lat, lng: request.dropoffLocation.lng),
                      onPropose: () => _openLocationPicker(context, controller, 'Dropoff Location', 'dropoff', request.dropoffLocation.name, request.dropoffLocation.lat, request.dropoffLocation.lng),
                      onAccept: () => _runNegotiationAction(() => controller.acceptTerm(widget.requestId, 'dropoff')),
                    ),

                    NegotiationFieldRow(
                      title: 'Tumpang Dates',
                      value: '${request.subscriptionStartDate.value} to ${request.subscriptionEndDate.value}',
                      isAccepted: request.subscriptionStartDate.isAccepted && request.subscriptionEndDate.isAccepted,
                      isRequestedByMe: request.subscriptionStartDate.requestedBy == controller.currentUserId,
                      onPropose: () => _openDateRangeProposalSheet(context, controller, request.subscriptionStartDate.value, request.subscriptionEndDate.value),
                      onAccept: () => _runNegotiationAction(() => controller.acceptTumpangDateRange(widget.requestId)),
                    ),

                    NegotiationFieldRow(
                      title: 'Pickup Time',
                      value: request.pickupTime.value,
                      isAccepted: request.pickupTime.isAccepted,
                      isRequestedByMe: request.pickupTime.requestedBy == controller.currentUserId,
                      onPropose: () => _openTimeProposalSheet(context, controller, request.pickupTime.value),
                      onAccept: () => _runNegotiationAction(() => controller.acceptTerm(widget.requestId, 'pickup_time')),
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
                      onAccept: () => _runNegotiationAction(() => controller.acceptTerm(widget.requestId, 'fee')),
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
