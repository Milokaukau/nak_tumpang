import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/propose_value_bottom_sheet.dart';

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
            var newValueParsed = fieldKey == 'fee' ? double.tryParse(newValue) ?? 0.0 : newValue;
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Viewing Request', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFB300), // Primary Yellow
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
      ),
      body: requestAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (request) {
          if (request == null) {
            return const Center(child: Text('Request no longer exists.'));
          }

          // 1. Fetch the counterpart's profile to get their real name
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
                // --- AVATAR & NAME HEADER ---
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                  ),
                  child: const Icon(Icons.person, size: 50, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  displayName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // --- PICKUP LOCATION ---
                _SectionCard(
                  title: 'Pickup Location',
                  child: Column(
                    children: [
                      _MapPlaceholder(request.pickupLocation.name),
                      const SizedBox(height: 12),
                      _ActionRow(
                        isAccepted: request.pickupLocation.isAccepted,
                        isRequestedByMe: request.pickupLocation.requestedBy == currentUser.id,
                        onPropose: () => _openProposalSheet(context, ref, 'Pickup Location', request.pickupLocation.name, 'pickup_location'),
                        onAccept: () => controller.acceptTerm(requestId, 'pickup_location'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- DROPOFF LOCATION ---
                _SectionCard(
                  title: 'Dropoff Location',
                  child: Column(
                    children: [
                      _MapPlaceholder(request.dropoffLocation.name),
                      const SizedBox(height: 12),
                      _ActionRow(
                        isAccepted: request.dropoffLocation.isAccepted,
                        isRequestedByMe: request.dropoffLocation.requestedBy == currentUser.id,
                        onPropose: () => _openProposalSheet(context, ref, 'Dropoff Location', request.dropoffLocation.name, 'dropoff_location'),
                        onAccept: () => controller.acceptTerm(requestId, 'dropoff_location'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- TUMPANG DATE (Start & End) ---
                _SectionCard(
                  title: 'Tumpang Date',
                  child: Column(
                    children: [
                      _ValueBox(request.subscriptionStartDate.value.isEmpty ? 'Start Date' : request.subscriptionStartDate.value),
                      const SizedBox(height: 8),
                      _ValueBox(request.subscriptionEndDate.value.isEmpty ? 'End Date' : request.subscriptionEndDate.value),
                      const SizedBox(height: 12),
                      // Notice: Using start date's acceptance status to govern the whole block for simplicity in UI,
                      // but you might want to split these in a real app.
                      _ActionRow(
                        isAccepted: request.subscriptionStartDate.isAccepted && request.subscriptionEndDate.isAccepted,
                        isRequestedByMe: request.subscriptionStartDate.requestedBy == currentUser.id,
                        onPropose: () => _openProposalSheet(context, ref, 'Start Date', request.subscriptionStartDate.value, 'subscription_start_date'), // Simplified for demo
                        onAccept: () async {
                          await controller.acceptTerm(requestId, 'subscription_start_date');
                          await controller.acceptTerm(requestId, 'subscription_end_date');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- PICKUP TIME ---
                _SectionCard(
                  title: 'Pickup Time',
                  child: Column(
                    children: [
                      _ValueBox(request.pickupTime.value.isEmpty ? 'Time' : request.pickupTime.value),
                      const SizedBox(height: 12),
                      _ActionRow(
                        isAccepted: request.pickupTime.isAccepted,
                        isRequestedByMe: request.pickupTime.requestedBy == currentUser.id,
                        onPropose: () => _openProposalSheet(context, ref, 'Pickup Time', request.pickupTime.value, 'pickup_time'),
                        onAccept: () => controller.acceptTerm(requestId, 'pickup_time'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- TUMPANG FEE ---
                _SectionCard(
                  title: 'Tumpang Fee',
                  child: Column(
                    children: [
                      _ValueBox(request.fee.value == 0 ? 'Fee' : 'RM ${request.fee.value.toStringAsFixed(2)}'),
                      const SizedBox(height: 12),
                      _ActionRow(
                        isAccepted: request.fee.isAccepted,
                        isRequestedByMe: request.fee.requestedBy == currentUser.id,
                        onPropose: () => _openProposalSheet(context, ref, 'Fee (RM)', request.fee.value.toString(), 'fee'),
                        onAccept: () => controller.acceptTerm(requestId, 'fee'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- NEGOTIATION DETAILS SUMMARY ---
                _SectionCard(
                  title: 'Negotiation Details',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SummaryText('Pickup Location', request.pickupLocation.name),
                      _SummaryText('Dropoff Location', request.dropoffLocation.name),
                      _SummaryText('Tumpang Start', request.subscriptionStartDate.value),
                      _SummaryText('Tumpang End', request.subscriptionEndDate.value),
                      _SummaryText('Pickup Time', request.pickupTime.value),
                      const SizedBox(height: 12),
                      _SummaryText('Tumpang Fee', 'RM ${request.fee.value.toStringAsFixed(2)} (30 days)'),
                      const SizedBox(height: 20),

                      // Final Accept / Reject Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.grey),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                controller.rejectEntireRequest(requestId);
                                Navigator.pop(context);
                              },
                              child: const Text('Reject', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFB300),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () async {
                                bool success = await controller.finalizeAgreement(request);
                                if (success && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agreement Finalized!')));
                                  // TODO: Navigate to Tumpang Summary Screen for Payment
                                } else if (!success && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All terms must be accepted first.')));
                                }
                              },
                              child: const Text('Accept', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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

// ============================================================================
// UI HELPER WIDGETS (Kept private to this file to match Figma perfectly)
// ============================================================================

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFFFB300), // Yellow Header
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _ValueBox extends StatelessWidget {
  final String value;
  const _ValueBox(this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, color: Colors.black87),
      ),
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  final String label;
  const _MapPlaceholder(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on, color: Colors.red, size: 32),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final bool isAccepted;
  final bool isRequestedByMe;
  final VoidCallback onPropose;
  final VoidCallback onAccept;

  const _ActionRow({
    required this.isAccepted,
    required this.isRequestedByMe,
    required this.onPropose,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    if (isAccepted) {
      return _ValueBox('✓ Accepted');
    }

    if (isRequestedByMe) {
      return _ValueBox('(Waiting for Acceptance)');
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              side: const BorderSide(color: Colors.grey),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: onPropose,
            // Note: Fixed typo from Figma mockups ("Purpose another" -> "Propose another")
            child: const Text('Propose another'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              side: const BorderSide(color: Colors.grey),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: onAccept,
            child: const Text('Accept'),
          ),
        ),
      ],
    );
  }
}

class _SummaryText extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryText(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 130,
              child: Text(label, style: const TextStyle(color: Colors.black87, fontSize: 14))
          ),
          const Text(' : '),
          Expanded(
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14))
          ),
        ],
      ),
    );
  }
}