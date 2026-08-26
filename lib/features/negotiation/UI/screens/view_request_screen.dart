import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/propose_value_bottom_sheet.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/negotiation_field_row.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/negotiation_summary_card.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/route_map_header.dart';

class ViewRequestScreen extends ConsumerWidget {
  final String requestId;

  const ViewRequestScreen({
    super.key,
    required this.requestId,
  });

  void _openProposalSheet(
      BuildContext context, WidgetRef ref, String title, String currentValue, String fieldKey) {
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

            // Validate fee input
            if (fieldKey == 'fee' && parsedFee == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a valid fee amount.')),
              );
              return; // Stop submission
            }

            final newValueParsed = fieldKey == 'fee' ? parsedFee! : newValue;

            ref.read(negotiationControllerProvider).proposeNewTerm(
              requestId,
              fieldKey,
              newValueParsed,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestAsync = ref.watch(singleRequestStreamProvider(requestId));
    final controller = ref.read(negotiationControllerProvider);
    final currentUser = ref.watch(mockAuthUserProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Viewing Request', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        centerTitle: true,
      ),
      body: requestAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (request) {
          if (request == null) {
            return const Center(child: Text('Request no longer exists.'));
          }

          final isDriver = currentUser.role == 'driver';
          final targetUserId = isDriver ? request.passengerId : request.driverId;
          final targetUserAsync = ref.watch(userProfileProvider(targetUserId));

          final displayName = targetUserAsync.maybeWhen(
            data: (userData) => userData?['name'] ?? userData?['full_name'] ?? targetUserId,
            orElse: () => 'Loading...',
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar & Name
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

                // Negotiation Fields
                NegotiationFieldRow(
                  title: 'Pickup Location',
                  value: request.pickupLocation.name,
                  isAccepted: request.pickupLocation.isAccepted,
                  isRequestedByMe: request.pickupLocation.requestedBy == currentUser.id,
                  topWidget: RouteMapHeader(label: request.pickupLocation.name),
                  onPropose: () => _openProposalSheet(context, ref, 'Pickup Location', request.pickupLocation.name, 'pickup_location'),
                  onAccept: () => controller.acceptTerm(requestId, 'pickup_location'),
                ),

                NegotiationFieldRow(
                  title: 'Dropoff Location',
                  value: request.dropoffLocation.name,
                  isAccepted: request.dropoffLocation.isAccepted,
                  isRequestedByMe: request.dropoffLocation.requestedBy == currentUser.id,
                  topWidget: RouteMapHeader(label: request.dropoffLocation.name),
                  onPropose: () => _openProposalSheet(context, ref, 'Dropoff Location', request.dropoffLocation.name, 'dropoff_location'),
                  onAccept: () => controller.acceptTerm(requestId, 'dropoff_location'),
                ),

                NegotiationFieldRow(
                  title: 'Tumpang Date',
                  value: request.subscriptionStartDate.value,
                  isAccepted: request.subscriptionStartDate.isAccepted && request.subscriptionEndDate.isAccepted,
                  isRequestedByMe: request.subscriptionStartDate.requestedBy == currentUser.id,
                  onPropose: () => _openProposalSheet(context, ref, 'Start Date', request.subscriptionStartDate.value, 'subscription_start_date'),
                  onAccept: () async {
                    await controller.acceptTerm(requestId, 'subscription_start_date');
                    await controller.acceptTerm(requestId, 'subscription_end_date');
                  },
                ),

                NegotiationFieldRow(
                  title: 'Pickup Time',
                  value: request.pickupTime.value,
                  isAccepted: request.pickupTime.isAccepted,
                  isRequestedByMe: request.pickupTime.requestedBy == currentUser.id,
                  onPropose: () => _openProposalSheet(context, ref, 'Pickup Time', request.pickupTime.value, 'pickup_time'),
                  onAccept: () => controller.acceptTerm(requestId, 'pickup_time'),
                ),

                NegotiationFieldRow(
                  title: 'Tumpang Fee',
                  value: request.fee.value.toString(),
                  isAccepted: request.fee.isAccepted,
                  isRequestedByMe: request.fee.requestedBy == currentUser.id,
                  onPropose: () => _openProposalSheet(context, ref, 'Fee (RM)', request.fee.value.toString(), 'fee'),
                  onAccept: () => controller.acceptTerm(requestId, 'fee'),
                ),

                // Final Summary Card
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
      ),
    );
  }
}