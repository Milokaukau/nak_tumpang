import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/request_list_card.dart';

class RequestListScreen extends ConsumerWidget { // <--- THIS is the class name it is looking for
  const RequestListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the dynamic stream we created in the view model
    final requestsAsyncValue = ref.watch(pendingRequestsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request List', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: requestsAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (requests) {
          if (requests.isEmpty) {
            return const Center(child: Text('No pending requests found.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return RequestListCard(request: request);
            },
          );
        },
      ),
    );
  }
}