import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/propose_value_bottom_sheet.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/negotiation_field_row.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/negotiation_summary_card.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/route_map_header.dart';

class ViewRequestScreen extends StatelessWidget {
  final String requestId;

  const ViewRequestScreen({
    super.key,
    required this.requestId,
  });

  void _openProposalSheet(
      BuildContext context, NegotiationViewModel controller, String title, String currentValue, String fieldKey) {
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
          onSubmit: (newValue) {
            final parsedFee = double.tryParse(newValue);
            if (fieldKey == 'fee' && parsedFee == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a valid fee amount.')),
              );
              return;
            }
            final newValueParsed = fieldKey == 'fee' ? parsedFee! : newValue;
            controller.proposeNewTerm(requestId, fieldKey, newValueParsed);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<NegotiationViewModel>(context, listen: false);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Viewing Request', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        centerTitle: true,
      ),
      body: StreamBuilder<TumpangRequest?>(
        stream: controller.singleRequestStream(requestId),
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

          final targetUserId = controller.currentUserRole == 'driver' ? request.passengerId : request.driverId;

          return FutureBuilder<Map<String, dynamic>?>(
            future: controller.getUserProfile(targetUserId),
            builder: (context, userSnapshot) {
              final userData = userSnapshot.data;
              final displayName = userData?['name'] ?? userData?['full_name'] ?? targetUserId;

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
                        lat: request.pickupLocation.lat, // Pass actual latitude
                        lng: request.pickupLocation.lng, // Pass actual longitude
                      ),
                      onPropose: () => _openProposalSheet(context, controller, 'Pickup Location', request.pickupLocation.name, 'pickup_location'),
                      onAccept: () => controller.acceptTerm(requestId, 'pickup_location'),
                    ),

                    NegotiationFieldRow(
                      title: 'Dropoff Location',
                      value: request.dropoffLocation.name,
                      isAccepted: request.dropoffLocation.isAccepted,
                      isRequestedByMe: request.dropoffLocation.requestedBy == controller.currentUserId,
                      topWidget: RouteMapHeader(
                        label: request.dropoffLocation.name,
                        lat: request.dropoffLocation.lat, // Pass actual latitude
                        lng: request.dropoffLocation.lng, // Pass actual longitude
                      ),
                      onPropose: () => _openProposalSheet(context, controller, 'Dropoff Location', request.dropoffLocation.name, 'dropoff_location'),
                      onAccept: () => controller.acceptTerm(requestId, 'dropoff_location'),
                    ),

                    NegotiationFieldRow(
                      title: 'Tumpang Date',
                      value: request.subscriptionStartDate.value,
                      isAccepted: request.subscriptionStartDate.isAccepted && request.subscriptionEndDate.isAccepted,
                      isRequestedByMe: request.subscriptionStartDate.requestedBy == controller.currentUserId,
                      onPropose: () => _openProposalSheet(context, controller, 'Start Date', request.subscriptionStartDate.value, 'subscription_start_date'),
                      onAccept: () async {
                        await controller.acceptTerm(requestId, 'subscription_start_date');
                        await controller.acceptTerm(requestId, 'subscription_end_date');
                      },
                    ),

                    NegotiationFieldRow(
                      title: 'Pickup Time',
                      value: request.pickupTime.value,
                      isAccepted: request.pickupTime.isAccepted,
                      isRequestedByMe: request.pickupTime.requestedBy == controller.currentUserId,
                      onPropose: () => _openProposalSheet(context, controller, 'Pickup Time', request.pickupTime.value, 'pickup_time'),
                      onAccept: () => controller.acceptTerm(requestId, 'pickup_time'),
                    ),

                    NegotiationFieldRow(
                      title: 'Tumpang Fee (RM)',
                      value: request.fee.value.toString(),
                      isAccepted: request.fee.isAccepted,
                      // Changed 'vm' to 'controller' here:
                      isRequestedByMe: request.fee.requestedBy == controller.currentUserId,
                      onPropose: () => _openProposalSheet(context, controller, 'Fee (RM)', request.fee.value.toString(), 'fee'),
                      onAccept: () => controller.acceptTerm(requestId, 'fee'),
                    ),

                    NegotiationSummaryCard(
                      request: request,
                      onReject: () {
                        controller.rejectEntireRequest(requestId);
                        Navigator.pop(context);
                      },
                      onAccept: () async {
                        bool success = await controller.finalizeAgreement(request);
                        if (success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agreement Finalized!')));
                        } else if (!success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All terms must be accepted first.')));
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