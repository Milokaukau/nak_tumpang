import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/request_list_card.dart';

class RequestListScreen extends StatefulWidget {
  final String role;
  final String? fallbackUserId;

  const RequestListScreen({
    super.key,
    this.role = 'driver',
    this.fallbackUserId,
  });

  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends State<RequestListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NegotiationViewModel>().fetchActiveTripAndInitialize(
        widget.role,
        fallbackUserId: widget.fallbackUserId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Request List',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Consumer<NegotiationViewModel>(
        builder: (context, vm, child) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (vm.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    Text(
                      vm.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        vm.fetchActiveTripAndInitialize(widget.role, fallbackUserId: widget.fallbackUserId);
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final stream = vm.pendingRequestsStream;
          if (stream == null) {
            return const Center(child: Text('No request stream available.'));
          }

          return StreamBuilder<List<TumpangRequest>>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Stream Error: ${snapshot.error}', textAlign: TextAlign.center),
                  ),
                );
              }

              final requests = snapshot.data ?? [];
              if (requests.isEmpty) {
                return const Center(
                  child: Text(
                    'No pending requests found.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  return RequestListCard(
                    key: ValueKey(requests[index].id),
                    request: requests[index],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}