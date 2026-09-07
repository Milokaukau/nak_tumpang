import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/UI/components/request_list_card.dart';

class RequestListScreen extends StatefulWidget {
  const RequestListScreen({super.key});

  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends State<RequestListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NegotiationViewModel>().fetchRequests();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Request List', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.black),
          onPressed: () => Navigator.maybePop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.black,
          indicatorColor: AppColors.primaryYellow,
          indicatorWeight: 3.0,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Pending Requests'),
            Tab(text: 'Completed'),
          ],
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
                    Text(vm.errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryYellow,
                        foregroundColor: AppColors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: () => vm.fetchRequests(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Pending
              RefreshIndicator(
                onRefresh: () => vm.refreshRequests(),
                child: vm.pendingRequests.isEmpty
                    ? Stack(
                  children: [
                    ListView(physics: const AlwaysScrollableScrollPhysics()),
                    const Center(
                      child: Text('No pending requests found.\nPull down to refresh.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                )
                    : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: vm.pendingRequests.length,
                  itemBuilder: (context, index) {
                    return RequestListCard(
                      key: ValueKey(vm.pendingRequests[index].id),
                      request: vm.pendingRequests[index],
                    );
                  },
                ),
              ),

              // Tab 2: Completed
              RefreshIndicator(
                onRefresh: () => vm.refreshRequests(),
                child: vm.completedRequests.isEmpty
                    ? Stack(
                  children: [
                    ListView(physics: const AlwaysScrollableScrollPhysics()),
                    const Center(
                      child: Text('No completed requests found.\nPull down to refresh.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                )
                    : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: vm.completedRequests.length,
                  itemBuilder: (context, index) {
                    return RequestListCard(
                      key: ValueKey(vm.completedRequests[index].id),
                      request: vm.completedRequests[index],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}