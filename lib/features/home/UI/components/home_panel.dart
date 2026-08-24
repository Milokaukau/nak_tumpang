import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_filter_options.dart';
import 'package:nak_tumpang/features/home/UI/components/route_option_card.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

class HomePanel extends StatelessWidget {
  // Constructor is now completely empty
  const HomePanel({super.key});

  @override
  Widget build(BuildContext context) {
    // The panel watches the ViewModel internally
    final viewModel = context.watch<HomeViewModel>();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: AppColors.greyBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              if (viewModel.currentPassenger != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Hello, ${viewModel.currentPassenger!['name']} 👋',
                    style: const TextStyle(fontSize: 16, color: AppColors.greyText),
                  ),
                ),

              const Text(
                'Available options',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              BaseFilterOptions(
                options: const ['Direct', 'Mixed'],
                selectedOption: viewModel.selectedFilter,
                onSelectionChanged: (option) {
                  viewModel.setFilter(option);
                },
              ),
              const SizedBox(height: 24),

              if (viewModel.isLoading)
                const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
              else ...[
                const RouteOptionCard(),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
                ),
                const RouteOptionCard(),
              ]
            ],
          ),
        );
      },
    );
  }
}