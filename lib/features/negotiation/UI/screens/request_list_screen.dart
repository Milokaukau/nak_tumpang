// lib/features/negotiation/UI/screens/request_list_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
        title: const Text('Request List', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(vm.errorMessage!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => vm.fetchActiveTripAndInitialize(widget.role),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (vm.pendingRequests.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => vm.refreshRequests(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text('No pending requests found.\nPull down to refresh.', textAlign: TextAlign.center)),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => vm.refreshRequests(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: vm.pendingRequests.length,
              itemBuilder: (context, index) {
                return RequestListCard(
                  key: ValueKey(vm.pendingRequests[index].id),
                  request: vm.pendingRequests[index],
                );
              },
            ),
          );
        },
      ),
    );
  }
}